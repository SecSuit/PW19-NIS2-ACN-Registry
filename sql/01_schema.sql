-- =============================================================================
-- PW19 - Registro NIS2/ACN
-- File      : 01_schema.sql
-- Scopo     : (ri)crea lo schema dedicato "nis2" partendo da una situazione pulita
-- Requisiti : PostgreSQL 18 (sviluppato e verificato su PostgreSQL 18.3)
-- Idempotenza: lo script elimina e ricrea lo schema; può essere rieseguito
--              quante volte si vuole. ATTENZIONE: cancella tutti i dati di nis2.
-- =============================================================================

SET client_encoding = 'UTF8';
SET client_min_messages = warning;

BEGIN;

DROP SCHEMA IF EXISTS nis2 CASCADE;

CREATE SCHEMA nis2;

COMMENT ON SCHEMA nis2 IS
  'Registro centralizzato di asset, servizi, dipendenze e responsabilità '
  'per la compilazione dei profili richiesti dall''ACN ai sensi del D.Lgs. 138/2024 (NIS2).';

COMMIT;

RESET client_min_messages;
