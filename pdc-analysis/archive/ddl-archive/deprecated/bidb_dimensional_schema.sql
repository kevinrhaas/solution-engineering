CREATE EXTENSION IF NOT EXISTS postgres_fdw;

CREATE SERVER if not exists remote_bidb
FOREIGN DATA WRAPPER postgres_fdw
OPTIONS (
  host '10.80.230.246',
  dbname 'bidb',
  port '5432'
);


CREATE USER MAPPING FOR CURRENT_USER
SERVER remote_bidb
OPTIONS (
  user 'bidb_ro',
  password '4aU94t8v+4d+W'
);


IMPORT FOREIGN SCHEMA public
FROM SERVER remote_bidb
INTO bidb_ext_demo;

