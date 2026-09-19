-- =============================================================================
-- PW19 - Registro NIS2/ACN
-- File      : 07_dati_test.sql
-- Scopo     : dataset simulato rappresentativo (tre soggetti NIS siciliani).
-- Dipende da: 06_funzioni_viste.sql
-- Idempotenza: svuota le tabelle dati (TRUNCATE ... RESTART IDENTITY) e le
--              ripopola: dopo ogni esecuzione gli identificativi sono sempre
--              gli stessi (Zagara = 1, Elymsol Energia = 2, TecPot = 3).
--
-- PRIVACY BY DESIGN - tutti i dati sono FITTIZI:
--  * organizzazioni, persone, indirizzi e contratti sono inventati; eventuali
--    omonimie con soggetti reali sono casuali;
--  * le partite IVA hanno formato e cifra di controllo validi ma sono generate
--    artificialmente; gli identificativi esteri sono fittizi;
--  * e-mail, PEC, siti e domini usano il TLD riservato ".example" (RFC 2606);
--  * gli indirizzi IP appartengono ai blocchi riservati alla documentazione
--    (RFC 5737 per IPv4, RFC 3849 per IPv6);
--  * non è memorizzato alcun codice fiscale di persona fisica.
-- =============================================================================

SET client_encoding = 'UTF8';
SET client_min_messages = warning;

BEGIN;

TRUNCATE nis2.dipendenza_fornitore, nis2.contratto, nis2.fornitore,
         nis2.dipendenza_asset, nis2.servizio_asset, nis2.servizio_paese,
         nis2.servizio, nis2.asset, nis2.assegnazione_ruolo, nis2.persona,
         nis2.spazio_ip, nis2.dominio, nis2.sede, nis2.organizzazione,
         nis2.organizzazione_storico, nis2.sede_storico, nis2.persona_storico,
         nis2.assegnazione_ruolo_storico, nis2.asset_storico, nis2.servizio_storico,
         nis2.fornitore_storico, nis2.contratto_storico, nis2.dipendenza_fornitore_storico,
         nis2.audit_log
RESTART IDENTITY CASCADE;

SELECT nis2.fn_imposta_motivo('Caricamento iniziale del dataset simulato');

-- -----------------------------------------------------------------------------
-- Organizzazioni
-- -----------------------------------------------------------------------------
INSERT INTO nis2.organizzazione
    (ragione_sociale, partita_iva, pec, telefono, email_funzionale, sito_web, tipologia_soggetto_codice,
     categoria_soggetto_codice, dimensione_codice, numero_dipendenti)
VALUES
    ('Zagara Neuro Therapeutics S.p.A.', '04738160870', 'amministrazione@pec.zagara-neuro.example',
     '+39 095 000 0100', 'nis@zagara-neuro.example',
     'https://www.zagara-neuro.example', 'SAN_FARMACEUTICI', 'ESSENZIALE', 'GRANDE', 412),
    ('Elymsol Energia S.p.A.',           '06182430824', 'direzione@pec.elymsol-energia.example',
     '+39 091 000 0200', 'nis@elymsol-energia.example',
     'https://www.elymsol-energia.example', 'EE_PRODUTTORI', 'ESSENZIALE', 'GRANDE', 286),
    ('TecPot Digital Services S.r.l.',   '03591720838', 'amministrazione@pec.tecpot-digital.example',
     '+39 090 000 0300', 'nis@tecpot-digital.example',
     'https://www.tecpot-digital.example', 'TIC_SERVIZI_GESTITI', 'IMPORTANTE', 'MEDIA', 138);

-- -----------------------------------------------------------------------------
-- Sedi
-- -----------------------------------------------------------------------------
INSERT INTO nis2.sede (organizzazione_id, tipo_sede, denominazione, indirizzo, cap, comune, provincia) VALUES
    (1, 'LEGALE',      'Sede legale Catania',              'Viale delle Zagare 18',          '95121', 'Catania',          'CT'),
    (1, 'PRODUTTIVA',  'Stabilimento di Paternò',          'Contrada Ciappe Bianche 7',      '95047', 'Paternò',          'CT'),
    (1, 'OPERATIVA',   'Polo R&S Catania',                 'Via dell''Innovazione 4',        '95121', 'Catania',          'CT'),
    (2, 'LEGALE',      'Sede legale Palermo',              'Via dei Mandorli 22',            '90141', 'Palermo',          'PA'),
    (2, 'OPERATIVA',   'Centro di telecontrollo Enna',     'Via Pergusa 110',                '94100', 'Enna',             'EN'),
    (2, 'IMPIANTO',    'Parco fotovoltaico Gela',          'Contrada Piana del Sole 1',      '93012', 'Gela',             'CL'),
    (2, 'IMPIANTO',    'Parco fotovoltaico Mazara',        'Contrada Borgo Sole 3',          '91026', 'Mazara del Vallo', 'TP'),
    (3, 'LEGALE',      'Sede legale Messina',              'Via del Faro 9',                 '98122', 'Messina',          'ME'),
    (3, 'DATA_CENTER', 'Data center Messina',              'Via dei Cavi Sottomarini 2',     '98158', 'Messina',          'ME'),
    (3, 'OPERATIVA',   'SOC Siracusa',                     'Via dei Papiri 31',              '96100', 'Siracusa',         'SR');

-- -----------------------------------------------------------------------------
-- Persone (solo dati di contatto professionali)
-- -----------------------------------------------------------------------------
INSERT INTO nis2.persona (nome, cognome, email, telefono) VALUES
    -- Zagara Neuro Therapeutics
    ('Giuseppe',       'Lo Cascio',   'g.locascio@zagara-neuro.example',          '+39 095 000 0101'),
    ('Carmela',        'Vitale',      'c.vitale@zagara-neuro.example',            '+39 095 000 0102'),
    ('Salvatore',      'Russo',       's.russo@zagara-neuro.example',             '+39 095 000 0103'),
    ('Rosaria',        'Grasso',      'r.grasso@zagara-neuro.example',            '+39 095 000 0104'),
    ('Antonino',       'Scuderi',     'a.scuderi@zagara-neuro.example',           '+39 095 000 0105'),
    ('Francesca',      'Privitera',   'dpo@zagara-neuro.example',                 '+39 095 000 0106'),
    ('Marco',          'Distefano',   'm.distefano@zagara-neuro.example',         '+39 095 000 0107'),
    ('Agata',          'Pappalardo',  'a.pappalardo@zagara-neuro.example',        '+39 095 000 0108'),
    -- Elymsol Energia
    ('Vincenzo',       'Lombardo',    'v.lombardo@elymsol-energia.example', '+39 091 000 0201'),
    ('Giovanna',       'Riccobono',   'g.riccobono@elymsol-energia.example','+39 091 000 0202'),
    ('Filippo',        'Cangemi',     'f.cangemi@elymsol-energia.example',  '+39 091 000 0203'),
    ('Daniela',        'Schifani',    'd.schifani@elymsol-energia.example', '+39 091 000 0204'),
    ('Calogero',       'Mangiapane',  'c.mangiapane@elymsol-energia.example','+39 0935 000 205'),
    ('Maria Concetta', 'Butera',      'mc.butera@elymsol-energia.example',  '+39 091 000 0206'),
    -- TecPot Digital Services
    ('Andrea',         'Crisafulli',  'a.crisafulli@tecpot-digital.example',      '+39 090 000 0301'),
    ('Federica',       'Saija',       'f.saija@tecpot-digital.example',           '+39 090 000 0302'),
    ('Luca',           'Mento',       'l.mento@tecpot-digital.example',           '+39 090 000 0303'),
    ('Paola',          'Cucinotta',   'p.cucinotta@tecpot-digital.example',       '+39 0931 000 304'),
    ('Sebastiano',     'Arena',       's.arena@tecpot-digital.example',           '+39 090 000 0305'),
    ('Giorgio',        'Previti',     'g.previti@tecpot-digital.example',         '+39 090 000 0306');

-- -----------------------------------------------------------------------------
-- Assegnazioni di ruolo (persona_id secondo l'ordine di inserimento sopra)
-- -----------------------------------------------------------------------------
INSERT INTO nis2.assegnazione_ruolo (organizzazione_id, persona_id, ruolo_codice, data_inizio, data_fine, atto_nomina) VALUES
    -- Zagara Neuro Therapeutics (1)
    (1,  1, 'RAPPRESENTANTE_LEGALE',    '2019-06-01', NULL, 'Delibera assembleare 30/05/2019'),
    (1,  1, 'MEMBRO_ORGANO_AMM',        '2019-06-01', NULL, 'Delibera assembleare 30/05/2019'),
    (1,  7, 'MEMBRO_ORGANO_AMM',        '2022-04-28', NULL, 'Delibera assembleare 28/04/2022'),
    (1,  8, 'PUNTO_CONTATTO',           '2025-01-20', NULL, 'Delibera CdA 15/01/2025'),
    (1,  3, 'SOSTITUTO_PUNTO_CONTATTO', '2025-01-20', NULL, 'Delibera CdA 15/01/2025'),
    (1,  4, 'REFERENTE_CSIRT',          '2025-11-15', NULL, 'Determina del punto di contatto n. 3/2025'),
    (1,  5, 'REFERENTE_CSIRT',          '2025-11-15', NULL, 'Determina del punto di contatto n. 3/2025'),
    (1,  4, 'CISO',                     '2021-09-01', NULL, 'Ordine di servizio 12/2021'),
    (1,  6, 'DPO',                      '2018-05-25', NULL, 'Atto di designazione 24/05/2018'),
    (1,  5, 'RESPONSABILE_IT',          '2020-02-01', NULL, 'Ordine di servizio 02/2020'),
    -- Elymsol Energia (2)
    (2,  9, 'RAPPRESENTANTE_LEGALE',    '2020-01-01', NULL, 'Delibera assembleare 18/12/2019'),
    (2,  9, 'MEMBRO_ORGANO_AMM',        '2020-01-01', NULL, 'Delibera assembleare 18/12/2019'),
    (2, 14, 'MEMBRO_ORGANO_AMM',        '2023-05-10', NULL, 'Delibera assembleare 10/05/2023'),
    (2, 10, 'PUNTO_CONTATTO',           '2025-01-27', NULL, 'Delibera CdA 22/01/2025'),
    (2, 11, 'SOSTITUTO_PUNTO_CONTATTO', '2025-01-27', NULL, 'Delibera CdA 22/01/2025'),
    (2, 12, 'REFERENTE_CSIRT',          '2025-11-20', NULL, 'Determina del punto di contatto n. 5/2025'),
    (2, 13, 'REFERENTE_CSIRT',          '2025-11-20', NULL, 'Determina del punto di contatto n. 5/2025'),
    (2, 12, 'CISO',                     '2022-03-01', NULL, 'Ordine di servizio 04/2022'),
    (2, 19, 'DPO',                      '2023-01-01', NULL, 'Contratto di servizio DPO esterno 2023'),
    (2, 13, 'RESPONSABILE_IT',          '2019-10-01', NULL, 'Ordine di servizio 09/2019'),
    -- TecPot Digital Services (3)
    (3, 15, 'RAPPRESENTANTE_LEGALE',    '2015-03-01', NULL, 'Atto costitutivo 2015'),
    (3, 15, 'MEMBRO_ORGANO_AMM',        '2015-03-01', NULL, 'Atto costitutivo 2015'),
    (3, 16, 'PUNTO_CONTATTO',           '2025-02-03', NULL, 'Determina dell''amministratore unico 01/2025'),
    (3, 17, 'SOSTITUTO_PUNTO_CONTATTO', '2025-02-03', NULL, 'Determina dell''amministratore unico 01/2025'),
    (3, 18, 'REFERENTE_CSIRT',          '2025-11-10', NULL, 'Determina del punto di contatto n. 1/2025'),
    (3, 18, 'CISO',                     '2021-01-01', NULL, 'Ordine di servizio 01/2021'),
    (3, 19, 'DPO',                      '2020-06-01', NULL, 'Atto di designazione 29/05/2020'),
    (3, 20, 'RESPONSABILE_IT',          '2018-09-01', NULL, 'Ordine di servizio 07/2018');

-- -----------------------------------------------------------------------------
-- Asset (sede e proprietario risolti per codice, non per id)
-- -----------------------------------------------------------------------------
INSERT INTO nis2.asset (organizzazione_id, codice, denominazione, descrizione, tipo_asset_codice,
                        classificazione_codice, criticita_livello, rto_minuti, rpo_minuti,
                        sede_id, proprietario_persona_id)
SELECT v.org, v.codice, v.den, v.descr, v.tipo, v.classif, v.crit, v.rto, v.rpo,
       (SELECT s.sede_id FROM nis2.sede s WHERE s.organizzazione_id = v.org AND s.denominazione = v.sede),
       (SELECT p.persona_id FROM nis2.persona p WHERE p.email = v.owner)
  FROM (VALUES
    -- Zagara Neuro Therapeutics
    (1, 'ZNT-ERP-01',  'ERP gestionale',                              'Ordini, magazzino, lotti e contabilità (SaaS).',                    'SAAS',         'RISERVATO',              3,  480,   60, NULL,                          'a.scuderi@zagara-neuro.example'),
    (1, 'ZNT-MES-01',  'MES di stabilimento',                         'Esecuzione e registrazione elettronica dei lotti di produzione.',   'APPLICAZIONE', 'RISERVATO',              4,  480,   15, 'Stabilimento di Paternò',  'm.distefano@zagara-neuro.example'),
    (1, 'ZNT-SER-01',  'Piattaforma di serializzazione',              'Serializzazione e tracciabilità delle confezioni di medicinali.',   'APPLICAZIONE', 'RISERVATO',              4,  120,    5, 'Stabilimento di Paternò',  'm.distefano@zagara-neuro.example'),
    (1, 'ZNT-LIMS-01', 'LIMS controllo qualità',                      'Gestione campioni e analisi del laboratorio di controllo qualità.', 'SAAS',         'STRETTAMENTE_RISERVATO', 3,  480,   60, NULL,                          'm.distefano@zagara-neuro.example'),
    (1, 'ZNT-DBFV-01', 'Database di farmacovigilanza',                'Segnalazioni di reazioni avverse e relative valutazioni.',          'DATI',         'STRETTAMENTE_RISERVATO', 4,  240,   15, 'Polo R&S Catania',            'c.vitale@zagara-neuro.example'),
    (1, 'ZNT-AD-01',   'Active Directory e MFA',                      'Identità, autenticazione a più fattori e criteri di accesso.',      'IDENTITA',     'RISERVATO',              4,   60,   15, 'Sede legale Catania',         'a.scuderi@zagara-neuro.example'),
    (1, 'ZNT-OT-01',   'Rete OT e PLC di confezionamento',            'Controllori e rete industriale delle linee di confezionamento.',    'OT',           'INTERNO',                4,  240,    0, 'Stabilimento di Paternò',  'm.distefano@zagara-neuro.example'),
    (1, 'ZNT-BCK-01',  'Backup immutabile in cloud',                  'Copie di sicurezza immutabili dei sistemi critici.',                'IAAS',         'RISERVATO',              3,  240,   60, NULL,                          'a.scuderi@zagara-neuro.example'),
    (1, 'ZNT-INT-01',  'Intranet aziendale',                          'Comunicazioni interne e modulistica.',                              'APPLICAZIONE', 'INTERNO',                1, NULL, NULL, 'Sede legale Catania',         'a.scuderi@zagara-neuro.example'),
    (1, 'ZNT-PDL-01',  'Postazioni di lavoro amministrative',         'Personal computer degli uffici amministrativi.',                    'HARDWARE',     'INTERNO',                2, 2880, 1440, 'Sede legale Catania',         'a.scuderi@zagara-neuro.example'),
    -- Elymsol Energia
    (2, 'ELY-SCADA-01','SCADA di telecontrollo impianti',             'Supervisione e comando dei parchi fotovoltaici.',                   'OT',           'RISERVATO',              4,   60,    0, 'Centro di telecontrollo Enna','c.mangiapane@elymsol-energia.example'),
    (2, 'ELY-RTU-01',  'RTU e inverter dei parchi',                   'Unità terminali remote e inverter di campo.',                       'OT',           'INTERNO',                4,  240,   15, 'Parco fotovoltaico Gela',     'c.mangiapane@elymsol-energia.example'),
    (2, 'ELY-EMS-01',  'Sistema di previsione e programmazione',      'Previsione della produzione e programmi di immissione.',            'APPLICAZIONE', 'RISERVATO',              3,  240,   60, 'Centro di telecontrollo Enna','c.mangiapane@elymsol-energia.example'),
    (2, 'ELY-HIS-01',  'Historian dei dati di produzione',            'Serie storiche di misura e produzione.',                            'DATI',         'INTERNO',                3,  480,   15, 'Centro di telecontrollo Enna','c.mangiapane@elymsol-energia.example'),
    (2, 'ELY-AD-01',   'Active Directory e accessi remoti',           'Identità e accesso remoto sicuro al centro di controllo.',          'IDENTITA',     'RISERVATO',              4,   60,   15, 'Sede legale Palermo',         'c.mangiapane@elymsol-energia.example'),
    (2, 'ELY-FW-01',   'Firewall di segregazione IT/OT',              'Separazione tra rete aziendale e rete di controllo.',               'RETE',         'RISERVATO',              4,   60,    0, 'Centro di telecontrollo Enna','c.mangiapane@elymsol-energia.example'),
    (2, 'ELY-CRM-01',  'CRM e fatturazione clienti',                  'Anagrafiche e fatturazione dei clienti business.',                  'SAAS',         'RISERVATO',              2, 1440,  240, NULL,                          'f.cangemi@elymsol-energia.example'),
    (2, 'ELY-WEB-01',  'Portale web istituzionale',                   'Sito pubblico dell''azienda.',                                      'SAAS',         'PUBBLICO',               1, NULL, NULL, NULL,                          'f.cangemi@elymsol-energia.example'),
    -- TecPot Digital Services
    (3, 'TDS-SIEM-01', 'Piattaforma SIEM/SOAR del SOC',               'Raccolta e correlazione eventi, automazione della risposta.',       'APPLICAZIONE', 'STRETTAMENTE_RISERVATO', 4,   60,   15, 'SOC Siracusa',                'p.cucinotta@tecpot-digital.example'),
    (3, 'TDS-RMM-01',  'Piattaforma RMM di gestione remota',          'Gestione e aggiornamento remoto dei sistemi dei clienti.',          'APPLICAZIONE', 'RISERVATO',              4,  120,   15, 'Data center Messina',         'g.previti@tecpot-digital.example'),
    (3, 'TDS-VIRT-01', 'Cluster di virtualizzazione',                 'Host di virtualizzazione e storage condiviso.',                     'HARDWARE',     'RISERVATO',              4,  120,   15, 'Data center Messina',         'g.previti@tecpot-digital.example'),
    (3, 'TDS-AD-01',   'Active Directory e PAM',                      'Identità e gestione degli accessi privilegiati.',                   'IDENTITA',     'STRETTAMENTE_RISERVATO', 4,   60,   15, 'Data center Messina',         'g.previti@tecpot-digital.example'),
    (3, 'TDS-TKT-01',  'Sistema di ticketing',                        'Gestione delle richieste e degli incidenti dei clienti.',           'SAAS',         'INTERNO',                3,  240,   60, NULL,                          'g.previti@tecpot-digital.example'),
    (3, 'TDS-GIT-01',  'Repository del codice sorgente',              'Versionamento del software sviluppato su commessa.',                'SAAS',         'RISERVATO',              2, 1440,  240, NULL,                          'g.previti@tecpot-digital.example')
  ) AS v (org, codice, den, descr, tipo, classif, crit, rto, rpo, sede, owner);

-- -----------------------------------------------------------------------------
-- Dipendenze tra asset (grafo aciclico)
-- -----------------------------------------------------------------------------
INSERT INTO nis2.dipendenza_asset (asset_id, asset_richiesto_id, tipo_dipendenza_codice)
SELECT (SELECT asset_id FROM nis2.asset WHERE codice = v.da),
       (SELECT asset_id FROM nis2.asset WHERE codice = v.a),
       v.tipo
  FROM (VALUES
    ('ZNT-MES-01',   'ZNT-AD-01',   'AUTENTICAZIONE'),
    ('ZNT-MES-01',   'ZNT-ERP-01',  'DATI'),
    ('ZNT-MES-01',   'ZNT-BCK-01',  'BACKUP'),
    ('ZNT-SER-01',   'ZNT-MES-01',  'DATI'),
    ('ZNT-SER-01',   'ZNT-AD-01',   'AUTENTICAZIONE'),
    ('ZNT-OT-01',    'ZNT-MES-01',  'DATI'),
    ('ZNT-ERP-01',   'ZNT-AD-01',   'AUTENTICAZIONE'),
    ('ZNT-LIMS-01',  'ZNT-AD-01',   'AUTENTICAZIONE'),
    ('ZNT-DBFV-01',  'ZNT-BCK-01',  'BACKUP'),
    ('ELY-SCADA-01', 'ELY-RTU-01',  'DATI'),
    ('ELY-SCADA-01', 'ELY-FW-01',   'RETE'),
    ('ELY-SCADA-01', 'ELY-AD-01',   'AUTENTICAZIONE'),
    ('ELY-RTU-01',   'ELY-FW-01',   'RETE'),
    ('ELY-HIS-01',   'ELY-SCADA-01','DATI'),
    ('ELY-EMS-01',   'ELY-HIS-01',  'DATI'),
    ('TDS-RMM-01',   'TDS-VIRT-01', 'ESECUZIONE'),
    ('TDS-RMM-01',   'TDS-AD-01',   'AUTENTICAZIONE'),
    ('TDS-SIEM-01',  'TDS-VIRT-01', 'ESECUZIONE'),
    ('TDS-SIEM-01',  'TDS-AD-01',   'AUTENTICAZIONE'),
    ('TDS-AD-01',    'TDS-VIRT-01', 'ESECUZIONE'),
    ('TDS-TKT-01',   'TDS-AD-01',   'AUTENTICAZIONE')
  ) AS v (da, a, tipo);

-- -----------------------------------------------------------------------------
-- Servizi, Stati di erogazione e asset di supporto
-- -----------------------------------------------------------------------------
INSERT INTO nis2.servizio (organizzazione_id, codice, denominazione, descrizione, criticita_livello,
                           utenti_impattati, perimetro_nis, responsabile_persona_id,
                           macro_area_codice, categoria_rilevanza_codice, valutazione_categoria)
SELECT v.org, v.codice, v.den, v.descr, v.crit, v.utenti, v.nis,
       (SELECT p.persona_id FROM nis2.persona p WHERE p.email = v.resp),
       c.macro, c.cat, c.valut
  FROM (VALUES
    (1, 'ZNT-SRV-PROD', 'Produzione di farmaci per terapie neurologiche',        'Produzione e rilascio dei lotti di medicinali.',                       4, 180000, true,  'm.distefano@zagara-neuro.example'),
    (1, 'ZNT-SRV-DIST', 'Distribuzione e tracciabilità dei medicinali',          'Consegna a grossisti e farmacie con verifica dei codici univoci.',     4,   1200, true,  'm.distefano@zagara-neuro.example'),
    (1, 'ZNT-SRV-FV',   'Farmacovigilanza',                                      'Raccolta e trasmissione delle segnalazioni di reazioni avverse.',      3, 180000, true,  'c.vitale@zagara-neuro.example'),
    (1, 'ZNT-SRV-RD',   'Ricerca e sviluppo preclinico',                         'Attività di laboratorio su nuove molecole.',                           2,     60, false, 'c.vitale@zagara-neuro.example'),
    (2, 'ELY-SRV-PROD', 'Produzione di energia elettrica da fonte fotovoltaica', 'Esercizio dei parchi fotovoltaici di Gela e Mazara del Vallo.',        4,  95000, true,  'c.mangiapane@elymsol-energia.example'),
    (2, 'ELY-SRV-PROG', 'Programmazione dell''immissione in rete',               'Previsione, programmi di immissione e scambio dati con il gestore di rete.', 4, 95000, true, 'c.mangiapane@elymsol-energia.example'),
    (2, 'ELY-SRV-VEND', 'Vendita di energia a clienti business',                 'Contratti di fornitura e fatturazione.',                               2,   3400, false, 'f.cangemi@elymsol-energia.example'),
    (3, 'TDS-SRV-MSP',  'Servizi gestiti di infrastruttura IT (MSP)',            'Gestione remota di server, reti e postazioni dei clienti.',            4,    140, true,  'g.previti@tecpot-digital.example'),
    (3, 'TDS-SRV-SOC',  'SOC gestito H24 (servizi di sicurezza gestiti)',        'Monitoraggio, rilevamento e risposta agli incidenti per i clienti.',   4,     60, true,  'p.cucinotta@tecpot-digital.example'),
    (3, 'TDS-SRV-DEV',  'Sviluppo software su commessa',                         'Progettazione e sviluppo di applicazioni per clienti.',                2,     25, false, 'a.crisafulli@tecpot-digital.example')
  ) AS v (org, codice, den, descr, crit, utenti, nis, resp)
  -- categorizzazione (Det. ACN 155238/2026): macro-area, categoria attribuita e,
  -- se diversa da quella pre-assegnata, la valutazione documentata (art. 3, c. 3)
  JOIN (VALUES
    ( 1, 'ZNT-SRV-PROD', 'PRODUZIONE',             'IMPATTO_ALTO',   'BIA 2026: un fermo della produzione interrompe la fornitura di farmaci salvavita per i pazienti neurologici.'),
    ( 2, 'ZNT-SRV-DIST', 'LOGISTICA',              'IMPATTO_ALTO',   'BIA 2026: la tracciabilità delle confezioni è obbligatoria; senza di essa i lotti non possono essere distribuiti.'),
    ( 3, 'ZNT-SRV-FV',   'MONITORAGGIO_CONTROLLO', 'IMPATTO_ALTO',   NULL),
    ( 4, 'ZNT-SRV-RD',   'RICERCA_SVILUPPO',       'IMPATTO_MEDIO',  NULL),
    ( 5, 'ELY-SRV-PROD', 'PRODUZIONE',             'IMPATTO_ALTO',   'BIA 2026: l''indisponibilità del telecontrollo ferma la produzione immessa in rete.'),
    ( 6, 'ELY-SRV-PROG', 'PRODUZIONE',             'IMPATTO_ALTO',   'BIA 2026: errori nei programmi di immissione incidono sul bilanciamento della rete.'),
    ( 7, 'ELY-SRV-VEND', 'GESTIONE_CLIENTI',       'IMPATTO_BASSO',  NULL),
    ( 8, 'TDS-SRV-MSP',  'PRODUZIONE',             'IMPATTO_ALTO',   'BIA 2026: il servizio gestito è erogato a soggetti NIS essenziali; un fermo si propaga ai clienti.'),
    ( 9, 'TDS-SRV-SOC',  'PRODUZIONE',             'IMPATTO_ALTO',   'BIA 2026: il SOC rileva gli incidenti dei clienti; un fermo ne ritarda la notifica.'),
    (10, 'TDS-SRV-DEV',  'RICERCA_SVILUPPO',       'IMPATTO_MEDIO',  NULL)
  ) AS c (ord, servizio, macro, cat, valut) ON c.servizio = v.codice
 ORDER BY c.ord;

INSERT INTO nis2.servizio_paese (servizio_id, paese_codice)
SELECT s.servizio_id, v.paese
  FROM (VALUES
    ('ZNT-SRV-PROD', 'IT'), ('ZNT-SRV-PROD', 'DE'), ('ZNT-SRV-DIST', 'IT'), ('ZNT-SRV-FV', 'IT'),
    ('ZNT-SRV-FV', 'DE'),   ('ZNT-SRV-RD', 'IT'),   ('ELY-SRV-PROD', 'IT'), ('ELY-SRV-PROG', 'IT'),
    ('ELY-SRV-VEND', 'IT'), ('TDS-SRV-MSP', 'IT'),  ('TDS-SRV-MSP', 'MT'),  ('TDS-SRV-SOC', 'IT'),
    ('TDS-SRV-DEV', 'IT')
  ) AS v (servizio, paese)
  JOIN nis2.servizio s ON s.codice = v.servizio;

INSERT INTO nis2.servizio_asset (servizio_id, asset_id, ruolo_asset)
SELECT s.servizio_id, a.asset_id, v.ruolo
  FROM (VALUES
    ('ZNT-SRV-PROD', 'ZNT-MES-01',  'PRIMARIO'), ('ZNT-SRV-PROD', 'ZNT-OT-01',   'PRIMARIO'),
    ('ZNT-SRV-PROD', 'ZNT-LIMS-01', 'PRIMARIO'), ('ZNT-SRV-PROD', 'ZNT-ERP-01',  'SUPPORTO'),
    ('ZNT-SRV-PROD', 'ZNT-AD-01',   'SUPPORTO'),
    ('ZNT-SRV-DIST', 'ZNT-SER-01',  'PRIMARIO'), ('ZNT-SRV-DIST', 'ZNT-ERP-01',  'PRIMARIO'),
    ('ZNT-SRV-DIST', 'ZNT-AD-01',   'SUPPORTO'),
    ('ZNT-SRV-FV',   'ZNT-DBFV-01', 'PRIMARIO'), ('ZNT-SRV-FV',   'ZNT-AD-01',   'SUPPORTO'),
    ('ZNT-SRV-FV',   'ZNT-BCK-01',  'SUPPORTO'),
    ('ZNT-SRV-RD',   'ZNT-LIMS-01', 'SUPPORTO'), ('ZNT-SRV-RD',   'ZNT-INT-01',  'SUPPORTO'),
    ('ELY-SRV-PROD', 'ELY-SCADA-01','PRIMARIO'), ('ELY-SRV-PROD', 'ELY-RTU-01',  'PRIMARIO'),
    ('ELY-SRV-PROD', 'ELY-FW-01',   'SUPPORTO'), ('ELY-SRV-PROD', 'ELY-AD-01',   'SUPPORTO'),
    ('ELY-SRV-PROG', 'ELY-EMS-01',  'PRIMARIO'), ('ELY-SRV-PROG', 'ELY-HIS-01',  'PRIMARIO'),
    ('ELY-SRV-PROG', 'ELY-SCADA-01','SUPPORTO'),
    ('ELY-SRV-VEND', 'ELY-CRM-01',  'PRIMARIO'), ('ELY-SRV-VEND', 'ELY-WEB-01',  'SUPPORTO'),
    ('TDS-SRV-MSP',  'TDS-RMM-01',  'PRIMARIO'), ('TDS-SRV-MSP',  'TDS-VIRT-01', 'PRIMARIO'),
    ('TDS-SRV-MSP',  'TDS-AD-01',   'SUPPORTO'), ('TDS-SRV-MSP',  'TDS-TKT-01',  'SUPPORTO'),
    ('TDS-SRV-SOC',  'TDS-SIEM-01', 'PRIMARIO'), ('TDS-SRV-SOC',  'TDS-VIRT-01', 'SUPPORTO'),
    ('TDS-SRV-SOC',  'TDS-AD-01',   'SUPPORTO'), ('TDS-SRV-SOC',  'TDS-TKT-01',  'SUPPORTO'),
    ('TDS-SRV-DEV',  'TDS-GIT-01',  'PRIMARIO')
  ) AS v (servizio, asset, ruolo)
  JOIN nis2.servizio s ON s.codice = v.servizio
  JOIN nis2.asset a    ON a.codice = v.asset;

-- -----------------------------------------------------------------------------
-- Fornitori (due coincidono con organizzazioni del registro)
-- -----------------------------------------------------------------------------
INSERT INTO nis2.fornitore (ragione_sociale, identificativo_fiscale, paese_codice, email_contatto, organizzazione_id) VALUES
    ('TecPot Digital Services S.r.l.',     '03591720838',     'IT', 'sicurezza@tecpot-digital.example',              3),
    ('Elymsol Energia S.p.A.',     '06182430824',     'IT', 'clienti.business@elymsol-energia.example', 2),
    ('Nuvola Mediterranea Cloud S.p.A.',   '07245910877',     'IT', 'security@nuvola-mediterranea.example',          NULL),
    ('Trinacria Fibra S.r.l.',             '05619380875',     'IT', 'noc@trinacria-fibra.example',                   NULL),
    ('Gestionali Etnei S.r.l.',            '08124700892',     'IT', 'sicurezza@gestionali-etnei.example',            NULL),
    ('Helix LabSystems Inc.',              'US5093318820',    'US', 'security@helix-labsystems.example',             NULL),
    ('Alpen Pharma Logistik GmbH',         'DE902718364',     'DE', 'it-security@alpen-pharmalogistik.example',      NULL),
    ('NordGrid Automation AB',             'SE559041872601',  'SE', 'psirt@nordgrid-automation.example',             NULL),
    ('CloudDesk Europe Ltd',               'IE8K47213X',      'IE', 'trust@clouddesk-europe.example',                NULL);

-- -----------------------------------------------------------------------------
-- Contratti
-- -----------------------------------------------------------------------------
INSERT INTO nis2.contratto (organizzazione_id, fornitore_id, codice, oggetto, data_inizio, data_fine,
                            clausole_sicurezza, dpa_art28, diritto_audit, notifica_incidenti_ore)
SELECT v.org, f.fornitore_id, v.codice, v.oggetto, v.inizio::date, v.fine::date, v.clausole, v.dpa, v.audit, v.notifica
  FROM (VALUES
    (1, 'TecPot Digital Services S.r.l.',   'C-ZNT-2024-011', 'Servizi gestiti di infrastruttura e SOC H24',        '2024-03-01', '2027-02-28', true,  true,  true,    24),
    (1, 'Gestionali Etnei S.r.l.',          'C-ZNT-2023-004', 'ERP in modalità SaaS',                               '2023-01-01', '2026-12-31', true,  true,  false,   72),
    (1, 'Helix LabSystems Inc.',            'C-ZNT-2024-019', 'LIMS in modalità SaaS',                              '2024-06-01', '2027-05-31', true,  true,  false,   48),
    (1, 'Elymsol Energia S.p.A.',   'C-ZNT-2022-002', 'Fornitura di energia elettrica allo stabilimento',   '2022-01-01', NULL,         false, false, false, NULL),
    (1, 'Alpen Pharma Logistik GmbH',       'C-ZNT-2025-007', 'Logistica a temperatura controllata',                '2025-01-01', '2027-12-31', false, true,  false, NULL),
    (1, 'Nuvola Mediterranea Cloud S.p.A.', 'C-ZNT-2024-021', 'Backup immutabile in cloud',                         '2024-09-01', '2027-08-31', true,  true,  true,    24),
    (2, 'NordGrid Automation AB',           'C-ELY-2023-015', 'Manutenzione del sistema SCADA e delle RTU',         '2023-05-01', '2027-04-30', true,  false, true,    24),
    (2, 'TecPot Digital Services S.r.l.',   'C-ELY-2024-003', 'SOC gestito H24 per ambienti IT e OT',               '2024-02-01', '2027-01-31', true,  true,  true,    12),
    (2, 'Trinacria Fibra S.r.l.',           'C-ELY-2022-009', 'Connettività dedicata centro di controllo-impianti', '2022-07-01', '2026-11-30', true,  false, false,   24),
    (2, 'CloudDesk Europe Ltd',             'C-ELY-2025-001', 'CRM in modalità SaaS',                               '2025-03-01', '2028-02-29', false, true,  false, NULL),
    (3, 'Nuvola Mediterranea Cloud S.p.A.', 'C-TDS-2023-001', 'Housing e infrastruttura IaaS del data center',      '2023-01-01', '2027-12-31', true,  true,  true,    24),
    (3, 'Trinacria Fibra S.r.l.',           'C-TDS-2023-002', 'Connettività ridondata del data center',             '2023-01-01', '2027-12-31', true,  false, false,   24),
    (3, 'CloudDesk Europe Ltd',             'C-TDS-2024-005', 'Piattaforma di ticketing in SaaS',                   '2024-04-01', '2027-03-31', true,  true,  false,   48),
    (3, 'Elymsol Energia S.p.A.',   'C-TDS-2022-004', 'Fornitura di energia elettrica al data center',      '2022-01-01', NULL,         false, false, false, NULL)
  ) AS v (org, fornitore, codice, oggetto, inizio, fine, clausole, dpa, audit, notifica)
  JOIN nis2.fornitore f ON f.ragione_sociale = v.fornitore
 ORDER BY v.org, v.codice;

-- -----------------------------------------------------------------------------
-- Dipendenze da terze parti (su servizio oppure su asset)
-- -----------------------------------------------------------------------------
INSERT INTO nis2.dipendenza_fornitore (contratto_id, servizio_id, asset_id, tipo_fornitura_codice,
                                       criterio_rilevanza_codice, codice_cpv, criticita_livello, paese_trattamento_codice)
SELECT c.contratto_id,
       (SELECT s.servizio_id FROM nis2.servizio s WHERE s.codice = v.servizio),
       (SELECT a.asset_id    FROM nis2.asset a    WHERE a.codice = v.asset),
       v.tipo, v.criterio, v.cpv, v.crit, v.paese
  FROM (VALUES
    ('C-ZNT-2024-011', 'ZNT-SRV-PROD', NULL,           'SICUREZZA_GESTITA', 'TIC',           '72000000-5', 4, 'IT'),
    ('C-ZNT-2024-011', NULL,           'ZNT-AD-01',    'SERVIZI_GESTITI',   'TIC',           '72600000-6', 4, 'IT'),
    ('C-ZNT-2023-004', NULL,           'ZNT-ERP-01',   'CLOUD_SAAS',        'TIC',           '48000000-8', 3, 'IT'),
    ('C-ZNT-2024-019', NULL,           'ZNT-LIMS-01',  'CLOUD_SAAS',        'TIC',           '48000000-8', 3, 'US'),
    ('C-ZNT-2022-002', 'ZNT-SRV-PROD', NULL,           'ENERGIA',           'NON_FUNGIBILE', '09310000-5', 4, NULL),
    ('C-ZNT-2025-007', 'ZNT-SRV-DIST', NULL,           'LOGISTICA',         'NON_FUNGIBILE', '60000000-8', 3, 'DE'),
    ('C-ZNT-2024-021', NULL,           'ZNT-BCK-01',   'CLOUD_IAAS',        'TIC',           '72300000-8', 3, 'IT'),
    ('C-ELY-2023-015', NULL,           'ELY-SCADA-01', 'MANUTENZIONE_OT',   'TIC',           '50000000-5', 4, 'SE'),
    ('C-ELY-2023-015', NULL,           'ELY-RTU-01',   'MANUTENZIONE_OT',   'TIC',           '50000000-5', 4, NULL),
    ('C-ELY-2024-003', 'ELY-SRV-PROD', NULL,           'SICUREZZA_GESTITA', 'TIC',           '72000000-5', 4, 'IT'),
    ('C-ELY-2022-009', 'ELY-SRV-PROG', NULL,           'CONNETTIVITA',      'TIC',           '64200000-8', 4, NULL),
    ('C-ELY-2025-001', NULL,           'ELY-CRM-01',   'CLOUD_SAAS',        'NON_RILEVANTE', '48000000-8', 2, 'IE'),
    ('C-TDS-2023-001', NULL,           'TDS-VIRT-01',  'DATA_CENTER',       'TIC',           '72300000-8', 4, 'IT'),
    ('C-TDS-2023-002', 'TDS-SRV-MSP',  NULL,           'CONNETTIVITA',      'TIC',           '64200000-8', 4, NULL),
    ('C-TDS-2024-005', NULL,           'TDS-TKT-01',   'CLOUD_SAAS',        'TIC',           '48000000-8', 3, 'IE'),
    ('C-TDS-2022-004', 'TDS-SRV-SOC',  NULL,           'ENERGIA',           'NON_FUNGIBILE', '09310000-5', 3, NULL)
  ) AS v (contratto, servizio, asset, tipo, criterio, cpv, crit, paese)
  JOIN nis2.contratto c ON c.codice = v.contratto
 ORDER BY c.contratto_id, v.servizio NULLS LAST, v.asset;

-- -----------------------------------------------------------------------------
-- Perimetro di rete (blocchi riservati alla documentazione, RFC 5737 / RFC 3849)
-- -----------------------------------------------------------------------------
INSERT INTO nis2.spazio_ip (organizzazione_id, rete, descrizione) VALUES
    (1, '192.0.2.0/26',       'Servizi esposti (portale, posta elettronica)'),
    (1, '192.0.2.64/27',      'Accesso remoto VPN dei fornitori'),
    (2, '198.51.100.0/25',    'Centro di telecontrollo e servizi esposti'),
    (2, '2001:db8:5e::/48',   'Servizi pubblici IPv6'),
    (3, '203.0.113.0/24',     'Data center e SOC'),
    (3, '2001:db8:9e1::/48',  'Servizi gestiti IPv6');

INSERT INTO nis2.dominio (organizzazione_id, nome_dominio, descrizione) VALUES
    (1, 'zagara-neuro.example',            'Sito istituzionale e posta elettronica'),
    (1, 'farmacovigilanza-zagara.example', 'Portale per le segnalazioni di farmacovigilanza'),
    (2, 'elymsol-energia.example',   'Sito istituzionale e posta elettronica'),
    (2, 'portale-elymsol.example',   'Area riservata clienti business'),
    (3, 'tecpot-digital.example',          'Sito istituzionale e posta elettronica'),
    (3, 'tecpot-soc.example',              'Portale clienti del SOC');

COMMIT;

-- -----------------------------------------------------------------------------
-- Eventi di manutenzione simulati (generano storico e audit dimostrativi)
-- -----------------------------------------------------------------------------
BEGIN;
SELECT nis2.fn_imposta_motivo('Esito della Business Impact Analysis 2026: RTO ridotto');
UPDATE nis2.asset SET rto_minuti = 240 WHERE codice = 'ZNT-MES-01';
COMMIT;

BEGIN;
CALL nis2.sp_sostituisci_titolare_ruolo(1, 'PUNTO_CONTATTO', 2, DATE '2025-10-01',
     'Riorganizzazione della funzione compliance', 'Delibera CdA 24/09/2025');
COMMIT;

RESET client_min_messages;
