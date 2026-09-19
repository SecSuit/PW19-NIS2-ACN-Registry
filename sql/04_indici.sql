-- =============================================================================
-- PW19 - Registro NIS2/ACN
-- File      : 04_indici.sql
-- Scopo     : indici secondari. PostgreSQL crea automaticamente un indice solo
--             per PRIMARY KEY, UNIQUE ed EXCLUDE, non per le FOREIGN KEY: senza
--             indice ogni DELETE/UPDATE sul padre e ogni join figlio->padre
--             richiederebbe una scansione sequenziale della tabella figlia.
-- Dipende da: 03_tabelle.sql
-- Idempotenza: CREATE INDEX IF NOT EXISTS
--
-- Criteri adottati
--  (1) indice su ogni FK non già coperta come prima colonna di PK/UNIQUE;
--  (2) indici sui campi di ricerca (ragione sociale, cognome) con lower() per
--      ricerche case-insensitive;
--  (3) indici PARZIALI per i sottoinsiemi interrogati dal profilo ACN
--      (asset critici, incarichi in corso, servizi nel perimetro NIS):
--      più piccoli, più selettivi e aggiornati solo quando serve;
--  (4) indici UNIQUE parziali per regole di business (una sola sede legale).
--  Le FK verso lookup a bassa cardinalità (es. dimensione_codice) non sono
--  indicizzate: la cancellazione di un valore di dominio è un evento raro.
-- =============================================================================

SET client_encoding = 'UTF8';
SET client_min_messages = warning;

BEGIN;

-- organizzazione ---------------------------------------------------------------
CREATE INDEX IF NOT EXISTS ix_organizzazione_tipologia
    ON nis2.organizzazione (tipologia_soggetto_codice);
CREATE INDEX IF NOT EXISTS ix_organizzazione_categoria
    ON nis2.organizzazione (categoria_soggetto_codice);
CREATE INDEX IF NOT EXISTS ix_organizzazione_ragione_sociale
    ON nis2.organizzazione (lower(ragione_sociale));

-- sede ---------------------------------------------------------------------------
-- (organizzazione_id) è già coperta da uq_sede_denominazione (prima colonna)
CREATE UNIQUE INDEX IF NOT EXISTS ux_sede_legale_unica
    ON nis2.sede (organizzazione_id) WHERE tipo_sede = 'LEGALE';
CREATE INDEX IF NOT EXISTS ix_sede_comune
    ON nis2.sede (comune);

-- persona ------------------------------------------------------------------------
CREATE UNIQUE INDEX IF NOT EXISTS ux_persona_email_lower
    ON nis2.persona (lower(email));
CREATE INDEX IF NOT EXISTS ix_persona_cognome_nome
    ON nis2.persona (lower(cognome), lower(nome));

-- assegnazione_ruolo -------------------------------------------------------------
CREATE INDEX IF NOT EXISTS ix_assegnazione_persona
    ON nis2.assegnazione_ruolo (persona_id);
CREATE INDEX IF NOT EXISTS ix_assegnazione_ruolo
    ON nis2.assegnazione_ruolo (ruolo_codice);
CREATE INDEX IF NOT EXISTS ix_assegnazione_org_ruolo_periodo
    ON nis2.assegnazione_ruolo (organizzazione_id, ruolo_codice, data_inizio, data_fine);
CREATE INDEX IF NOT EXISTS ix_assegnazione_in_corso
    ON nis2.assegnazione_ruolo (organizzazione_id, ruolo_codice) WHERE data_fine IS NULL;

-- asset --------------------------------------------------------------------------
-- (organizzazione_id) è già coperta da uq_asset_codice (prima colonna)
CREATE INDEX IF NOT EXISTS ix_asset_tipo
    ON nis2.asset (tipo_asset_codice);
CREATE INDEX IF NOT EXISTS ix_asset_classificazione
    ON nis2.asset (classificazione_codice);
CREATE INDEX IF NOT EXISTS ix_asset_sede
    ON nis2.asset (sede_id);
CREATE INDEX IF NOT EXISTS ix_asset_proprietario
    ON nis2.asset (proprietario_persona_id);
CREATE INDEX IF NOT EXISTS ix_asset_critici
    ON nis2.asset (organizzazione_id, criticita_livello DESC) WHERE criticita_livello >= 3;

-- servizio -----------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS ix_servizio_responsabile
    ON nis2.servizio (responsabile_persona_id);
CREATE INDEX IF NOT EXISTS ix_servizio_criticita
    ON nis2.servizio (criticita_livello);
CREATE INDEX IF NOT EXISTS ix_servizio_perimetro_nis
    ON nis2.servizio (organizzazione_id) WHERE perimetro_nis;

-- tabelle ponte (la seconda colonna della PK non è coperta) -----------------------
CREATE INDEX IF NOT EXISTS ix_servizio_paese_paese
    ON nis2.servizio_paese (paese_codice);
CREATE INDEX IF NOT EXISTS ix_servizio_asset_asset
    ON nis2.servizio_asset (asset_id);
CREATE INDEX IF NOT EXISTS ix_dipendenza_asset_richiesto
    ON nis2.dipendenza_asset (asset_richiesto_id);
CREATE INDEX IF NOT EXISTS ix_dipendenza_asset_tipo
    ON nis2.dipendenza_asset (tipo_dipendenza_codice);

-- fornitore e contratto ----------------------------------------------------------
CREATE INDEX IF NOT EXISTS ix_fornitore_paese
    ON nis2.fornitore (paese_codice);
CREATE INDEX IF NOT EXISTS ix_fornitore_ragione_sociale
    ON nis2.fornitore (lower(ragione_sociale));
CREATE INDEX IF NOT EXISTS ix_contratto_fornitore
    ON nis2.contratto (fornitore_id);
CREATE INDEX IF NOT EXISTS ix_contratto_scadenza
    ON nis2.contratto (data_fine) WHERE data_fine IS NOT NULL;

-- dipendenza_fornitore -----------------------------------------------------------
-- (contratto_id) è già coperta da uq_dipendenza_fornitore (prima colonna)
CREATE INDEX IF NOT EXISTS ix_dipendenza_fornitore_servizio
    ON nis2.dipendenza_fornitore (servizio_id) WHERE servizio_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_dipendenza_fornitore_asset
    ON nis2.dipendenza_fornitore (asset_id) WHERE asset_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_dipendenza_fornitore_tipo
    ON nis2.dipendenza_fornitore (tipo_fornitura_codice);
CREATE INDEX IF NOT EXISTS ix_dipendenza_fornitore_criterio
    ON nis2.dipendenza_fornitore (criterio_rilevanza_codice);
CREATE INDEX IF NOT EXISTS ix_dipendenza_fornitore_paese
    ON nis2.dipendenza_fornitore (paese_trattamento_codice);

-- perimetro di rete ---------------------------------------------------------------
-- (rete) è già indicizzata dall'indice GiST del vincolo ex_spazio_ip_sovrapposto
CREATE INDEX IF NOT EXISTS ix_spazio_ip_organizzazione
    ON nis2.spazio_ip (organizzazione_id);
CREATE INDEX IF NOT EXISTS ix_dominio_organizzazione
    ON nis2.dominio (organizzazione_id);

COMMIT;

RESET client_min_messages;
