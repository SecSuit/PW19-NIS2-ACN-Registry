-- =============================================================================
-- PW19 - Registro NIS2/ACN
-- File      : 08_query_profilo_acn.sql
-- Scopo     : query che generano le porzioni del profilo ACN per ogni azienda
--             e comandi di esportazione in CSV.
-- Dipende da: deploy completo (00_run_all.sql)
-- Uso       : eseguibile per intero o per singola query (selezionare il testo
--             nel Query Tool di pgAdmin 4 e premere F5). Sola lettura.
-- =============================================================================

SET client_encoding = 'UTF8';

-- -----------------------------------------------------------------------------
-- Q1. Elenco delle organizzazioni con classificazione NIS
-- -----------------------------------------------------------------------------
SELECT organizzazione_id, ragione_sociale, partita_iva, categoria_soggetto,
       settore, allegato, tipologia_soggetto, dimensione, sede_legale
  FROM nis2.v_organizzazione
 ORDER BY organizzazione_id;

-- -----------------------------------------------------------------------------
-- Q2. Asset critici per azienda (livello ALTA o CRITICA)
-- -----------------------------------------------------------------------------
SELECT ragione_sociale, codice, denominazione, tipo_asset, criticita,
       rto_minuti, rpo_minuti, ubicazione, proprietario, servizi_supportati
  FROM nis2.v_asset_critici
 ORDER BY organizzazione_id, criticita_livello DESC, codice;

-- -----------------------------------------------------------------------------
-- Q3. Servizi erogati per azienda
-- -----------------------------------------------------------------------------
SELECT ragione_sociale, codice, denominazione, criticita, utenti_impattati,
       perimetro_nis, paesi_erogazione, asset_collegati, dipendenze_dirette, responsabile
  FROM nis2.v_servizi_erogati
 ORDER BY organizzazione_id, criticita_livello DESC, codice;

-- -----------------------------------------------------------------------------
-- Q4. Dipendenze da terze parti per azienda
-- -----------------------------------------------------------------------------
SELECT ragione_sociale, tipo_oggetto, codice_oggetto, fornitore, paese_fornitore,
       tipo_fornitura, criterio_rilevanza, codice_cpv, criticita, contratto,
       scadenza_contratto, clausole_sicurezza, dpa_art28, paese_trattamento_dati
  FROM nis2.v_dipendenze_terze_parti
 ORDER BY organizzazione_id, criticita_livello DESC, fornitore;

-- -----------------------------------------------------------------------------
-- Q5. Punti di contatto e responsabilità comunicate all'ACN, per azienda
-- -----------------------------------------------------------------------------
SELECT ragione_sociale, ruolo, nome, cognome, email, telefono, data_inizio
  FROM nis2.v_punti_contatto
 ORDER BY organizzazione_id, ruolo_codice, cognome;

-- -----------------------------------------------------------------------------
-- Q6. Sintesi per azienda: numero di elementi per sezione del profilo
-- -----------------------------------------------------------------------------
SELECT ragione_sociale,
       count(*) FILTER (WHERE sezione = '2-PUNTI_DI_CONTATTO')   AS punti_contatto,
       count(*) FILTER (WHERE sezione = '3-SPAZIO_IP')           AS blocchi_ip,
       count(*) FILTER (WHERE sezione = '4-DOMINI')              AS domini,
       count(*) FILTER (WHERE sezione = '5-SERVIZI')             AS servizi,
       count(*) FILTER (WHERE sezione = '6-ASSET_CRITICI')       AS asset_critici,
       count(*) FILTER (WHERE sezione = '7-FORNITORI_RILEVANTI') AS fornitori_rilevanti,
       count(*) FILTER (WHERE sezione = '8-CATEGORIZZAZIONE')    AS attivita_categorizzate,
       count(*)                                                  AS totale_righe
  FROM nis2.v_profilo_acn
 GROUP BY organizzazione_id, ragione_sociale
 ORDER BY organizzazione_id;

-- -----------------------------------------------------------------------------
-- Q7. Analisi di supply chain: fornitori extra UE o contratti senza clausole
--     di sicurezza / DPA (elementi da presidiare ai sensi dell'art. 24)
-- -----------------------------------------------------------------------------
SELECT ragione_sociale, fornitore, paese_fornitore, fornitore_ue,
       paese_trattamento_dati, clausole_sicurezza, dpa_art28, diritto_audit, criticita
  FROM nis2.v_dipendenze_terze_parti
 WHERE NOT fornitore_ue
    OR NOT clausole_sicurezza
    OR (paese_trattamento_dati IS NOT NULL AND NOT dpa_art28)
 ORDER BY organizzazione_id, fornitore;

-- -----------------------------------------------------------------------------
-- Q8. Contratti di fornitori rilevanti in scadenza nei prossimi 120 giorni
-- -----------------------------------------------------------------------------
SELECT DISTINCT ragione_sociale, fornitore, contratto, scadenza_contratto,
       scadenza_contratto - current_date AS giorni_residui
  FROM nis2.v_dipendenze_terze_parti
 WHERE criterio_rilevanza <> 'NON_RILEVANTE'
   AND scadenza_contratto BETWEEN current_date AND current_date + 120
 ORDER BY scadenza_contratto;

-- -----------------------------------------------------------------------------
-- Q8b. Elenco categorizzato delle attività e dei servizi (art. 30 D.Lgs. 138/2024;
--      Det. ACN 155238/2026): macro-area, categoria pre-assegnata e attribuita
-- -----------------------------------------------------------------------------
SELECT ragione_sociale, modello, codice, denominazione, macro_area,
       categoria_predefinita, categoria_attribuita, scostamento, valutazione_categoria
  FROM nis2.v_categorizzazione_attivita
 ORDER BY organizzazione_id, ordine_categoria DESC, codice;

-- -----------------------------------------------------------------------------
-- Q9. Profilo ACN completo tramite VISTA (tutte le aziende)
-- -----------------------------------------------------------------------------
SELECT *
  FROM nis2.v_profilo_acn
 ORDER BY organizzazione_id, sezione, progressivo;

-- -----------------------------------------------------------------------------
-- Q10. Profilo ACN di una singola azienda tramite FUNZIONE
--      (1 = Zagara Neuro Therapeutics, 2 = Elymsol Energia, 3 = TecPot)
-- -----------------------------------------------------------------------------
SELECT * FROM nis2.fn_profilo_acn(1);

-- -----------------------------------------------------------------------------
-- Q11. Profilo ACN come testo CSV pronto (una cella): utile quando non si ha
--      accesso al file system del server
-- -----------------------------------------------------------------------------
SELECT nis2.fn_profilo_acn_csv(1)      AS csv_virgola;
SELECT nis2.fn_profilo_acn_csv(1, ';') AS csv_punto_e_virgola_excel;

-- =============================================================================
-- ESPORTAZIONE IN CSV - due modalità, entrambe lato CLIENT
-- =============================================================================
--
-- (A) pgAdmin 4 - Query Tool (nessun privilegio speciale, nessun percorso)
--     1. eseguire:  SELECT * FROM nis2.fn_profilo_acn(1);
--     2. nella barra sopra la griglia "Data Output" premere il pulsante
--        "Save results to file" (icona con la freccia verso il basso, oppure F8):
--        pgAdmin salva il risultato in un file .csv nella cartella Download.
--        Separatore, virgolette ed encoding si impostano in
--        File > Preferences > Query Tool > CSV/TXT Output.
--
-- (B) PSQL Tool di pgAdmin (o psql) - meta-comando \copy: il file viene scritto
--     dal CLIENT con i permessi dell'utente Windows, quindi anche in Documenti.
--     NON funziona nel Query Tool (i meta-comandi con la barra rovesciata sono
--     riconosciuti solo da psql). Esempio:
--       \cd 'C:/Users/aroci/OneDrive/Desktop/nis2_acn/export'
--       \copy (SELECT * FROM nis2.fn_profilo_acn(1)) TO 'profilo_acn_1_zagara_neuro_therapeutics.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
--     Lo script export/esporta_profili_csv.sql esporta i profili di tutte le aziende.
--
-- Nota: il comando SQL "COPY ... TO 'percorso'" (senza barra rovesciata) scrive
-- invece sul SERVER con l'account del servizio PostgreSQL, che su Windows non ha
-- accesso alla cartella Documenti dell'utente: per questo non è utilizzato.
-- =============================================================================
