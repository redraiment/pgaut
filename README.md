# PgAUT

## Introduction

PgAUT – is a PostgreSQL extension which implements MySQL `on update current_timestamp`.

PgAUT method is based on [event trigger](https://www.postgresql.org/docs/current/static/sql-createeventtrigger.html).

## Authors

* Zhang, Zepeng ([redraiment@gmail.com](mailto:redraiment@gmail.com))

## Availability

PgAUT is released as an extension and not available in default PostgreSQL installation. It is available from [github](https://github.com/redraiment/pgaut.git) under the same license as [PostgreSQL](http://www.postgresql.org/about/licence/) and supports PostgreSQL 9.1+.

## Installation

Before build and install PgAUT you should ensure following:

* PostgreSQL version is 9.1 or higher.
* Your PATH variable is configured so that pg_config command available.

Typical installation procedure may look like this:

```sh
$ git clone https://github.com/redraiment/pgaut.git
$ cd pgaut
$ sudo make USE_PGXS=1 install
$ psql DB -c "CREATE EXTENSION pgaut"
```

## Usage

PgAUT offsets a domain type of `timestamp`, named `auto_update_timestamp`.

For any `auto_update_timestamp` column in a table, you can assign the current timestamp as the auto-update value. An auto-updated column is automatically updated to the current timestamp when the value of any other column in the row is changed from its current value.

## Example

```sql
create extension pgaut;

create table users (
  id bigserial primary key,
  name text not null,
  created_at timestamp default current_timestamp,
  updated_at auto_update_timestamp default current_timestamp
);

insert into users (name) values ('redraiment') returning *;
--
--  id |    name    |         created_at         |         updated_at
-- ----+------------+----------------------------+----------------------------
--   1 | redraiment | 2018-10-17 20:45:20.479757 | 2018-10-17 20:45:20.479757
-- (1 row)
-- 
-- INSERT 0 1
--

update users set name = 'Zhang, Zepeng' returning *;
--
--  id |     name      |         created_at         |         updated_at         
-- ----+---------------+----------------------------+----------------------------
--   1 | Zhang, Zepeng | 2018-10-17 20:45:20.479757 | 2018-10-17 20:56:22.116274
-- (1 row)
-- 
-- UPDATE 1
--
```
