-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION pgaut" to load this file. \quit

--

create domain auto_update_timestamp as timestamp;

--

create or replace function aut_generate_trigger_handler_name(_schema_name text, _table_name text) returns text as $$
  select format('%s.%s_on_update_current_timestamp_handler', _schema_name, _table_name)
$$ language sql immutable;

create or replace function aut_generate_trigger_name(_schema_name text, _table_name text) returns text as $$
  select format('%s_%s_on_update_current_timestamp_trigger', _schema_name, _table_name)
$$ language sql immutable;

--

--
-- create or replace auto-update column trigger handler function
-- for specified schema and table.
--
create or replace function aut_update_handler(_schema_name text, _table_name text) returns text as $$
declare
  _sql text;
  _handler_name text;
begin
  -- fetch the name of auto_update_timestamp type columns,
  -- then generate `new.<column-name> := clock_timestamp();` sql statement.
  select
    string_agg('  new.' || column_name || ' := clock_timestamp();', E'\n')
  into
    _sql
  from
    information_schema.columns
  where
    table_schema = _schema_name
    and table_name = _table_name
    and domain_name = 'auto_update_timestamp';

  _handler_name := @extschema@.aut_generate_trigger_handler_name(_schema_name, _table_name);

  execute format($SQL$
create or replace function %s() returns trigger as $HANDLER$
begin
  %s
  return new;
end;
$HANDLER$ language plpgsql;
$SQL$, _handler_name, _sql);

  return _handler_name;
end;
$$ language plpgsql;

--

create or replace function aut_delete_handler(_schema_name text, _table_name text) returns void as $$
begin
  execute format('drop function %s()', @extschema@.aut_generate_trigger_handler_name(_schema_name, _table_name));
end;
$$ language plpgsql;

--

create or replace function aut_create_trigger(_schema_name text, _table_name text) returns void as $$
declare
  _handler_name text;
  _trigger_name text;
begin
  _trigger_name := @extschema@.aut_generate_trigger_name(_schema_name, _table_name);
  _handler_name := @extschema@.aut_generate_trigger_handler_name(_schema_name, _table_name);
  
  execute format($SQL$
create trigger %s
 before update on %s.%s
 for each row execute
 procedure %s()
$SQL$, _trigger_name, _schema_name, _table_name, _handler_name);
end;
$$ language plpgsql;

--

create or replace function aut_create_or_alter_table_event_trigger_handler() returns event_trigger as $$
declare
  _e record;
  _schema_name text;
  _table_name text;
begin
  for _e in select * from pg_event_trigger_ddl_commands() loop
    if _e.object_type = 'table' then
      -- get the schema name and table name of the effected tables
      select
        pg_namespace.nspname,
        pg_class.relname
      into
        _schema_name,
        _table_name
      from
        pg_class
      inner join
        pg_namespace
      on
        pg_class.relnamespace = pg_namespace.oid
      where
        pg_class.oid = _e.objid;

      if _e.command_tag = 'CREATE TABLE' then
        perform @extschema@.aut_update_handler(_schema_name, _table_name);
        perform @extschema@.aut_create_trigger(_schema_name, _table_name);
      elsif _e.command_tag = 'ALTER TABLE' then
        perform @extschema@.aut_update_handler(_schema_name, _table_name);
      end if;
    end if;
  end loop;
end;
$$ language plpgsql;

create event trigger aut_create_or_alter_table_event_trigger
  on ddl_command_end
  when tag in ('CREATE TABLE', 'ALTER TABLE')
  execute procedure @extschema@.aut_create_or_alter_table_event_trigger_handler();

create or replace function aut_drop_table_event_trigger_handler() returns event_trigger as $$
declare
  _e record;
begin
  for _e in select * from pg_event_trigger_dropped_objects() loop
    if _e.object_type = 'table' then
      perform @extschema@.aut_delete_handler(_e.schema_name, _e.object_name);
    end if;
  end loop;
end;
$$ language plpgsql;

create event trigger aut_drop_table_event_trigger
  on sql_drop
  when tag in ('DROP TABLE')
  execute procedure @extschema@.aut_drop_table_event_trigger_handler();
