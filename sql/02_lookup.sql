-- =============================================================================
-- PW19 - Registro NIS2/ACN
-- File      : 02_lookup.sql
-- Scopo     : funzioni di validazione e tabelle di dominio (lookup) con i valori
--             ammessi. Le lookup sostituiscono il testo libero: ogni attributo
--             categoriale delle tabelle principali è una FK verso questi domini.
-- Dipende da: 01_schema.sql
-- Idempotenza: CREATE ... IF NOT EXISTS, CREATE OR REPLACE, INSERT ... ON CONFLICT
-- Chiavi     : codici naturali brevi e stabili (es. 'ESSENZIALE'), che rendono
--             leggibili dati e query; ON UPDATE CASCADE sulle FK che li usano.
-- =============================================================================

SET client_encoding = 'UTF8';
SET client_min_messages = warning;

BEGIN;

-- -----------------------------------------------------------------------------
-- Funzioni di validazione usate nei vincoli CHECK (IMMUTABLE: dipendono solo
-- dall'argomento, quindi utilizzabili in CHECK e indici)
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION nis2.fn_piva_valida(p_piva text)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
STRICT
AS $$
DECLARE
    v_somma  integer := 0;
    v_cifra  integer;
    v_i      integer;
BEGIN
    -- Formato: esattamente 11 cifre
    IF p_piva !~ '^[0-9]{11}$' THEN
        RETURN false;
    END IF;
    -- Algoritmo di controllo della partita IVA italiana (cifra di controllo = 11a cifra):
    -- cifre in posizione dispari sommate così come sono; cifre in posizione pari
    -- raddoppiate e ridotte di 9 se maggiori di 9.
    FOR v_i IN 1..10 LOOP
        v_cifra := substr(p_piva, v_i, 1)::integer;
        IF v_i % 2 = 0 THEN
            v_cifra := v_cifra * 2;
            IF v_cifra > 9 THEN
                v_cifra := v_cifra - 9;
            END IF;
        END IF;
        v_somma := v_somma + v_cifra;
    END LOOP;
    RETURN (10 - v_somma % 10) % 10 = substr(p_piva, 11, 1)::integer;
END;
$$;

COMMENT ON FUNCTION nis2.fn_piva_valida(text) IS
  'Restituisce true se la stringa è una partita IVA italiana formalmente valida '
  '(11 cifre e cifra di controllo corretta). Usata nei vincoli CHECK.';

CREATE OR REPLACE FUNCTION nis2.fn_email_valida(p_email text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
STRICT
AS $$
    SELECT p_email ~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}$';
$$;

COMMENT ON FUNCTION nis2.fn_email_valida(text) IS
  'Verifica sintattica di un indirizzo e-mail (parte locale, dominio, TLD di almeno 2 lettere).';

-- -----------------------------------------------------------------------------
-- Paesi (ISO 3166-1 alpha-2)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS nis2.paese (
    codice        char(2)      PRIMARY KEY,
    denominazione varchar(80)  NOT NULL UNIQUE,
    membro_ue     boolean      NOT NULL,
    CONSTRAINT ck_paese_codice CHECK (codice ~ '^[A-Z]{2}$')
);
COMMENT ON TABLE  nis2.paese IS 'Dominio dei Paesi (ISO 3166-1 alpha-2); il flag membro_ue individua i trasferimenti extra UE.';
COMMENT ON COLUMN nis2.paese.codice        IS 'Codice ISO 3166-1 alpha-2 (chiave naturale).';
COMMENT ON COLUMN nis2.paese.denominazione IS 'Nome del Paese in italiano.';
COMMENT ON COLUMN nis2.paese.membro_ue     IS 'true se il Paese è Stato membro dell''Unione europea.';

INSERT INTO nis2.paese (codice, denominazione, membro_ue) VALUES
    ('IT', 'Italia',          true),
    ('DE', 'Germania',        true),
    ('FR', 'Francia',         true),
    ('ES', 'Spagna',          true),
    ('IE', 'Irlanda',         true),
    ('NL', 'Paesi Bassi',     true),
    ('SE', 'Svezia',          true),
    ('MT', 'Malta',           true),
    ('CH', 'Svizzera',        false),
    ('GB', 'Regno Unito',     false),
    ('US', 'Stati Uniti',     false)
ON CONFLICT (codice) DO NOTHING;

-- -----------------------------------------------------------------------------
-- Categorizzazione delle attività e dei servizi (art. 30 D.Lgs. 138/2024;
-- Determinazione ACN n. 155238/2026 e relativi Allegati 1 e 2)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS nis2.modello_categorizzazione (
    codice        varchar(20)  PRIMARY KEY,
    denominazione varchar(120) NOT NULL UNIQUE,
    ambito        text         NOT NULL
);
COMMENT ON TABLE  nis2.modello_categorizzazione IS 'Modelli di categorizzazione adottati dalla Determinazione ACN n. 155238/2026 (Allegato 1 e Allegato 2).';
COMMENT ON COLUMN nis2.modello_categorizzazione.codice        IS 'Codice del modello (chiave naturale).';
COMMENT ON COLUMN nis2.modello_categorizzazione.denominazione IS 'Denominazione del modello.';
COMMENT ON COLUMN nis2.modello_categorizzazione.ambito        IS 'Soggetti a cui il modello si applica (art. 2, commi 2 e 3, della determinazione).';

INSERT INTO nis2.modello_categorizzazione (codice, denominazione, ambito) VALUES
    ('ALLEGATO_1', 'Modello di categorizzazione – Allegato 1', 'Tipologie di soggetto dei numeri 1, 2, 5, 6, 7 e 10 dell''Allegato I, dei numeri da 1 a 5 dell''Allegato II e del numero 1 dell''Allegato IV del decreto NIS.'),
    ('ALLEGATO_2', 'Modello di categorizzazione – Allegato 2', 'Tutti gli altri soggetti NIS.')
ON CONFLICT (codice) DO NOTHING;

CREATE TABLE IF NOT EXISTS nis2.categoria_rilevanza (
    codice        varchar(20)  PRIMARY KEY,
    denominazione varchar(40)  NOT NULL UNIQUE,
    ordine        smallint     NOT NULL UNIQUE,
    CONSTRAINT ck_categoria_rilevanza_ordine CHECK (ordine BETWEEN 1 AND 4)
);
COMMENT ON TABLE  nis2.categoria_rilevanza IS 'Categorie di rilevanza delle attività e dei servizi (Determinazione ACN n. 155238/2026, art. 2, c. 4).';
COMMENT ON COLUMN nis2.categoria_rilevanza.codice        IS 'Codice della categoria (chiave naturale).';
COMMENT ON COLUMN nis2.categoria_rilevanza.denominazione IS 'Denominazione ufficiale della categoria.';
COMMENT ON COLUMN nis2.categoria_rilevanza.ordine        IS 'Ordinamento crescente per impatto (1 = minimo, 4 = alto).';

INSERT INTO nis2.categoria_rilevanza (codice, denominazione, ordine) VALUES
    ('IMPATTO_MINIMO', 'Impatto minimo', 1),
    ('IMPATTO_BASSO',  'Impatto basso',  2),
    ('IMPATTO_MEDIO',  'Impatto medio',  3),
    ('IMPATTO_ALTO',   'Impatto alto',   4)
ON CONFLICT (codice) DO NOTHING;

CREATE TABLE IF NOT EXISTS nis2.macro_area (
    codice        varchar(30)  PRIMARY KEY,
    denominazione varchar(80)  NOT NULL UNIQUE,
    descrizione   text         NOT NULL
);
COMMENT ON TABLE  nis2.macro_area IS 'Le dieci macro-aree del modello di categorizzazione ACN (Determinazione n. 155238/2026, Allegati 1 e 2).';
COMMENT ON COLUMN nis2.macro_area.codice        IS 'Codice della macro-area (chiave naturale).';
COMMENT ON COLUMN nis2.macro_area.denominazione IS 'Denominazione della macro-area come da allegato.';
COMMENT ON COLUMN nis2.macro_area.descrizione   IS 'Sintesi delle attività e dei servizi compresi nella macro-area.';

INSERT INTO nis2.macro_area (codice, denominazione, descrizione) VALUES
    ('MONITORAGGIO_CONTROLLO', 'Monitoraggio e controllo',            'Supporto ai vertici, coordinamento della sicurezza informatica e fisica, continuità operativa, controllo di qualità e di conformità, anche in relazione ai fornitori.'),
    ('PRODUZIONE',             'Produzione di beni e servizi',        'Pianificazione operativa, processi operativi, erogazione dei servizi ai clienti, gestione operativa dei fornitori, manutenzione degli impianti produttivi.'),
    ('RICERCA_SVILUPPO',       'Ricerca, sviluppo e progettazione',   'Studio di nuove tecnologie, prototipazione, collaborazioni scientifiche, progetti, proprietà intellettuale, ingegnerizzazione.'),
    ('GESTIONE_FINANZIARIA',   'Gestione finanziaria',                'Pianificazione finanziaria, flussi di cassa, fatturazione e pagamenti, contabilità, bilancio, tesoreria.'),
    ('GESTIONE_CLIENTI',       'Gestione dei clienti',                'Onboarding, anagrafica e CRM, help desk di primo livello, richieste commerciali, soddisfazione dei clienti.'),
    ('RISORSE_UMANE',          'Gestione delle risorse umane',        'Selezione, amministrazione del personale, valutazione, formazione.'),
    ('LOGISTICA',              'Logistica',                           'Flussi logistici, magazzino, preparazione degli ordini, spedizioni, distribuzione e consegna.'),
    ('COMUNICAZIONE_MARKETING','Comunicazione e marketing',           'Canali digitali e social, relazioni esterne, brand, contenuti, eventi e campagne.'),
    ('GESTIONE_AMMINISTRATIVA','Gestione amministrativa',             'Immobili, contratti, gestione amministrativa dei fornitori, adempimenti fiscali, pratiche autorizzative.'),
    ('ALTRI',                  'Altri servizi e attività',            'Attività e servizi che non rientrano nelle altre macro-aree.')
ON CONFLICT (codice) DO NOTHING;

CREATE TABLE IF NOT EXISTS nis2.macro_area_modello (
    modello_codice               varchar(20) NOT NULL
        REFERENCES nis2.modello_categorizzazione (codice) ON UPDATE CASCADE ON DELETE RESTRICT,
    macro_area_codice            varchar(30) NOT NULL
        REFERENCES nis2.macro_area (codice) ON UPDATE CASCADE ON DELETE RESTRICT,
    categoria_predefinita_codice varchar(20) NOT NULL
        REFERENCES nis2.categoria_rilevanza (codice) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT pk_macro_area_modello PRIMARY KEY (modello_codice, macro_area_codice)
);
COMMENT ON TABLE  nis2.macro_area_modello IS 'Categoria di rilevanza pre-assegnata a ciascuna macro-area in ciascun modello (Allegati 1 e 2 della Determinazione ACN n. 155238/2026).';
COMMENT ON COLUMN nis2.macro_area_modello.modello_codice               IS 'Modello di categorizzazione (FK).';
COMMENT ON COLUMN nis2.macro_area_modello.macro_area_codice            IS 'Macro-area (FK).';
COMMENT ON COLUMN nis2.macro_area_modello.categoria_predefinita_codice IS 'Categoria di rilevanza pre-assegnata dal modello (FK).';

INSERT INTO nis2.macro_area_modello (modello_codice, macro_area_codice, categoria_predefinita_codice)
SELECT m.modello, v.macro_area,
       CASE WHEN v.macro_area = 'LOGISTICA' AND m.modello = 'ALLEGATO_2' THEN 'IMPATTO_MINIMO' ELSE v.categoria END
  FROM (VALUES ('ALLEGATO_1'), ('ALLEGATO_2')) AS m (modello)
 CROSS JOIN (VALUES
    ('MONITORAGGIO_CONTROLLO',  'IMPATTO_ALTO'),
    ('PRODUZIONE',              'IMPATTO_MEDIO'),
    ('RICERCA_SVILUPPO',        'IMPATTO_MEDIO'),
    ('GESTIONE_FINANZIARIA',    'IMPATTO_BASSO'),
    ('GESTIONE_CLIENTI',        'IMPATTO_BASSO'),
    ('RISORSE_UMANE',           'IMPATTO_BASSO'),
    ('LOGISTICA',               'IMPATTO_BASSO'),      -- Allegato 2: impatto minimo
    ('COMUNICAZIONE_MARKETING', 'IMPATTO_MINIMO'),
    ('GESTIONE_AMMINISTRATIVA', 'IMPATTO_MINIMO'),
    ('ALTRI',                   'IMPATTO_MINIMO')
 ) AS v (macro_area, categoria)
ON CONFLICT (modello_codice, macro_area_codice) DO NOTHING;

-- -----------------------------------------------------------------------------
-- Classificazione NIS: settore -> sottosettore -> tipologia di soggetto
-- (struttura degli Allegati I e II della Direttiva (UE) 2022/2555 e del D.Lgs. 138/2024)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS nis2.settore (
    codice        varchar(40)  PRIMARY KEY,
    denominazione varchar(150) NOT NULL UNIQUE,
    allegato      varchar(3)   NOT NULL,
    modello_categorizzazione_codice varchar(20)
        REFERENCES nis2.modello_categorizzazione (codice) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT ck_settore_allegato CHECK (allegato IN ('I', 'II', 'III', 'IV'))
);
COMMENT ON TABLE  nis2.settore IS 'Settori NIS con l''allegato del D.Lgs. 138/2024 in cui sono elencati (I = alta criticità, II = altri settori critici).';
COMMENT ON COLUMN nis2.settore.codice        IS 'Codice mnemonico del settore (chiave naturale).';
COMMENT ON COLUMN nis2.settore.denominazione IS 'Denominazione del settore come da allegato.';
COMMENT ON COLUMN nis2.settore.allegato      IS 'Allegato di riferimento (I, II, III, IV).';
COMMENT ON COLUMN nis2.settore.modello_categorizzazione_codice IS 'Modello di categorizzazione applicabile (Det. ACN 155238/2026, art. 2); NULL se da determinare.';

INSERT INTO nis2.settore (codice, denominazione, allegato, modello_categorizzazione_codice) VALUES
    -- modello secondo l'art. 2, c. 2, della Det. 155238/2026 (numeri dell'Allegato I e II)
    ('ENERGIA',             'Energia',                                                 'I',  'ALLEGATO_1'),  -- I.1
    ('TRASPORTI',           'Trasporti',                                               'I',  'ALLEGATO_1'),  -- I.2
    ('BANCARIO',            'Settore bancario',                                        'I',  'ALLEGATO_2'),  -- I.3
    ('MERCATI_FINANZIARI',  'Infrastrutture dei mercati finanziari',                   'I',  'ALLEGATO_2'),  -- I.4
    ('SANITARIO',           'Settore sanitario',                                       'I',  'ALLEGATO_1'),  -- I.5
    ('ACQUA_POTABILE',      'Acqua potabile',                                          'I',  'ALLEGATO_1'),  -- I.6
    ('ACQUE_REFLUE',        'Acque reflue',                                            'I',  'ALLEGATO_1'),  -- I.7
    ('INFRA_DIGITALI',      'Infrastrutture digitali',                                 'I',  'ALLEGATO_2'),  -- I.8
    ('GESTIONE_TIC_B2B',    'Gestione dei servizi TIC (business-to-business)',         'I',  'ALLEGATO_2'),  -- I.9
    ('SPAZIO',              'Spazio',                                                  'I',  NULL),          -- da verificare sulla numerazione dell'Allegato I
    ('POSTALI',             'Servizi postali e di corriere',                           'II', 'ALLEGATO_1'),  -- II.1
    ('RIFIUTI',             'Gestione dei rifiuti',                                    'II', 'ALLEGATO_1'),  -- II.2
    ('CHIMICA',             'Fabbricazione, produzione e distribuzione di sostanze chimiche', 'II', 'ALLEGATO_1'),  -- II.3
    ('ALIMENTI',            'Produzione, trasformazione e distribuzione di alimenti',  'II', 'ALLEGATO_1'),  -- II.4
    ('FABBRICAZIONE',       'Fabbricazione',                                           'II', 'ALLEGATO_1'),  -- II.5
    ('FORNITORI_DIGITALI',  'Fornitori di servizi digitali',                           'II', 'ALLEGATO_2'),  -- II.6
    ('RICERCA',             'Ricerca',                                                 'II', 'ALLEGATO_2')   -- II.7
ON CONFLICT (codice) DO NOTHING;

CREATE TABLE IF NOT EXISTS nis2.sottosettore (
    codice          varchar(40)  PRIMARY KEY,
    settore_codice  varchar(40)  NOT NULL
        REFERENCES nis2.settore (codice) ON UPDATE CASCADE ON DELETE RESTRICT,
    denominazione   varchar(150) NOT NULL,
    CONSTRAINT uq_sottosettore_denominazione UNIQUE (settore_codice, denominazione)
);
COMMENT ON TABLE  nis2.sottosettore IS 'Sottosettori NIS. I settori privi di sottosettori hanno un unico sottosettore omonimo, così la catena tipologia -> sottosettore -> settore resta sempre completa (niente dipendenze transitive).';
COMMENT ON COLUMN nis2.sottosettore.codice         IS 'Codice mnemonico del sottosettore (chiave naturale).';
COMMENT ON COLUMN nis2.sottosettore.settore_codice IS 'Settore di appartenenza (FK settore).';
COMMENT ON COLUMN nis2.sottosettore.denominazione  IS 'Denominazione del sottosettore.';

INSERT INTO nis2.sottosettore (codice, settore_codice, denominazione) VALUES
    ('ENERGIA_ELETTRICA',  'ENERGIA',            'Energia elettrica'),
    ('TELERISCALDAMENTO',  'ENERGIA',            'Teleriscaldamento e teleraffrescamento'),
    ('PETROLIO',           'ENERGIA',            'Petrolio'),
    ('GAS',                'ENERGIA',            'Gas'),
    ('IDROGENO',           'ENERGIA',            'Idrogeno'),
    ('SANITARIO',          'SANITARIO',          'Settore sanitario (senza sottosettori)'),
    ('ACQUA_POTABILE',     'ACQUA_POTABILE',     'Acqua potabile (senza sottosettori)'),
    ('INFRA_DIGITALI',     'INFRA_DIGITALI',     'Infrastrutture digitali (senza sottosettori)'),
    ('GESTIONE_TIC_B2B',   'GESTIONE_TIC_B2B',   'Gestione dei servizi TIC B2B (senza sottosettori)'),
    ('RIFIUTI',            'RIFIUTI',            'Gestione dei rifiuti (senza sottosettori)'),
    ('ALIMENTI',           'ALIMENTI',           'Alimenti (senza sottosettori)')
ON CONFLICT (codice) DO NOTHING;

CREATE TABLE IF NOT EXISTS nis2.tipologia_soggetto (
    codice              varchar(50)  PRIMARY KEY,
    sottosettore_codice varchar(40)  NOT NULL
        REFERENCES nis2.sottosettore (codice) ON UPDATE CASCADE ON DELETE RESTRICT,
    denominazione       varchar(250) NOT NULL,
    CONSTRAINT uq_tipologia_denominazione UNIQUE (sottosettore_codice, denominazione)
);
COMMENT ON TABLE  nis2.tipologia_soggetto IS 'Tipologia di soggetto prevista dagli allegati (es. produttori di energia elettrica, fornitori di servizi gestiti).';
COMMENT ON COLUMN nis2.tipologia_soggetto.codice              IS 'Codice mnemonico della tipologia (chiave naturale).';
COMMENT ON COLUMN nis2.tipologia_soggetto.sottosettore_codice IS 'Sottosettore di appartenenza (FK sottosettore); da esso deriva il settore.';
COMMENT ON COLUMN nis2.tipologia_soggetto.denominazione       IS 'Descrizione della tipologia di soggetto.';

INSERT INTO nis2.tipologia_soggetto (codice, sottosettore_codice, denominazione) VALUES
    ('EE_PRODUTTORI',            'ENERGIA_ELETTRICA', 'Produttori di energia elettrica'),
    ('EE_DISTRIBUTORI',          'ENERGIA_ELETTRICA', 'Gestori del sistema di distribuzione di energia elettrica'),
    ('EE_FORNITORI',             'ENERGIA_ELETTRICA', 'Imprese elettriche che svolgono la funzione di fornitura'),
    ('SAN_PRESTATORI',           'SANITARIO',         'Prestatori di assistenza sanitaria'),
    ('SAN_FARMACEUTICI',         'SANITARIO',         'Fabbricanti di prodotti farmaceutici di base e di preparati farmaceutici (NACE Rev. 2, sezione C, divisione 21)'),
    ('ACQUA_FORNITORI',          'ACQUA_POTABILE',    'Fornitori e distributori di acque destinate al consumo umano'),
    ('DIG_CLOUD',                'INFRA_DIGITALI',    'Fornitori di servizi di cloud computing'),
    ('DIG_DATA_CENTER',          'INFRA_DIGITALI',    'Fornitori di servizi di data center'),
    ('TIC_SERVIZI_GESTITI',      'GESTIONE_TIC_B2B',  'Fornitori di servizi gestiti'),
    ('TIC_SICUREZZA_GESTITI',    'GESTIONE_TIC_B2B',  'Fornitori di servizi di sicurezza gestiti'),
    ('RIFIUTI_GESTORI',          'RIFIUTI',           'Gestori dei rifiuti'),
    ('ALIMENTI_PRODUZIONE',      'ALIMENTI',          'Imprese alimentari che si occupano di produzione, trasformazione e distribuzione all''ingrosso')
ON CONFLICT (codice) DO NOTHING;

-- -----------------------------------------------------------------------------
-- Categoria del soggetto e dimensione d'impresa
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS nis2.categoria_soggetto (
    codice        varchar(20)  PRIMARY KEY,
    denominazione varchar(80)  NOT NULL UNIQUE,
    descrizione   text         NOT NULL
);
COMMENT ON TABLE  nis2.categoria_soggetto IS 'Categoria NIS del soggetto: essenziale o importante (art. 6 D.Lgs. 138/2024; art. 3 Direttiva (UE) 2022/2555).';
COMMENT ON COLUMN nis2.categoria_soggetto.codice        IS 'Codice della categoria (chiave naturale).';
COMMENT ON COLUMN nis2.categoria_soggetto.denominazione IS 'Denominazione della categoria.';
COMMENT ON COLUMN nis2.categoria_soggetto.descrizione   IS 'Criterio sintetico di attribuzione della categoria.';

INSERT INTO nis2.categoria_soggetto (codice, denominazione, descrizione) VALUES
    ('ESSENZIALE', 'Soggetto essenziale', 'Tra gli altri: soggetti dell''Allegato I che superano i massimali delle medie imprese, o individuati come tali dall''Autorità nazionale competente.'),
    ('IMPORTANTE', 'Soggetto importante', 'Soggetti degli Allegati I e II che non sono essenziali (tipicamente medie imprese dell''Allegato I e soggetti dell''Allegato II).')
ON CONFLICT (codice) DO NOTHING;

CREATE TABLE IF NOT EXISTS nis2.dimensione_impresa (
    codice        varchar(10)  PRIMARY KEY,
    denominazione varchar(40)  NOT NULL UNIQUE,
    ordine        smallint     NOT NULL UNIQUE
);
COMMENT ON TABLE  nis2.dimensione_impresa IS 'Classe dimensionale secondo la Raccomandazione 2003/361/CE (micro, piccola, media, grande impresa).';
COMMENT ON COLUMN nis2.dimensione_impresa.codice        IS 'Codice della classe dimensionale (chiave naturale).';
COMMENT ON COLUMN nis2.dimensione_impresa.denominazione IS 'Denominazione della classe dimensionale.';
COMMENT ON COLUMN nis2.dimensione_impresa.ordine        IS 'Ordinamento crescente per dimensione.';

INSERT INTO nis2.dimensione_impresa (codice, denominazione, ordine) VALUES
    ('MICRO',   'Microimpresa',    1),
    ('PICCOLA', 'Piccola impresa', 2),
    ('MEDIA',   'Media impresa',   3),
    ('GRANDE',  'Grande impresa',  4)
ON CONFLICT (codice) DO NOTHING;

-- -----------------------------------------------------------------------------
-- Domini per asset e servizi
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS nis2.livello_criticita (
    livello       smallint     PRIMARY KEY,
    denominazione varchar(20)  NOT NULL UNIQUE,
    descrizione   text         NOT NULL,
    CONSTRAINT ck_livello_criticita_range CHECK (livello BETWEEN 1 AND 4)
);
COMMENT ON TABLE  nis2.livello_criticita IS 'Scala ordinale di criticità (1 = bassa ... 4 = critica). La chiave numerica consente confronti (livello >= 3 = asset critico).';
COMMENT ON COLUMN nis2.livello_criticita.livello       IS 'Valore ordinale della criticità, da 1 a 4 (chiave naturale).';
COMMENT ON COLUMN nis2.livello_criticita.denominazione IS 'Etichetta del livello.';
COMMENT ON COLUMN nis2.livello_criticita.descrizione   IS 'Impatto atteso in caso di indisponibilità o compromissione.';

INSERT INTO nis2.livello_criticita (livello, denominazione, descrizione) VALUES
    (1, 'BASSA',   'Impatto trascurabile sui servizi; ripristino differibile.'),
    (2, 'MEDIA',   'Impatto limitato e circoscritto; degrado tollerabile per alcuni giorni.'),
    (3, 'ALTA',    'Impatto rilevante su servizi NIS; ripristino entro 24 ore.'),
    (4, 'CRITICA', 'Interruzione di servizi essenziali o rischio per salute e sicurezza; ripristino in ore.')
ON CONFLICT (livello) DO NOTHING;

CREATE TABLE IF NOT EXISTS nis2.tipo_asset (
    codice        varchar(20)  PRIMARY KEY,
    denominazione varchar(80)  NOT NULL UNIQUE,
    descrizione   text         NOT NULL
);
COMMENT ON TABLE  nis2.tipo_asset IS 'Tipologia di asset (hardware, software, dati, rete, OT, cloud, sito).';
COMMENT ON COLUMN nis2.tipo_asset.codice        IS 'Codice della tipologia (chiave naturale).';
COMMENT ON COLUMN nis2.tipo_asset.denominazione IS 'Denominazione della tipologia.';
COMMENT ON COLUMN nis2.tipo_asset.descrizione   IS 'Esempi e perimetro della tipologia.';

INSERT INTO nis2.tipo_asset (codice, denominazione, descrizione) VALUES
    ('HARDWARE',     'Hardware',                  'Server, storage, postazioni, apparati fisici.'),
    ('APPLICAZIONE', 'Applicazione software',     'Applicativi gestionali e di produzione installati on-premise.'),
    ('SAAS',         'Servizio applicativo cloud','Applicazioni fruite in modalità Software as a Service.'),
    ('IAAS',         'Infrastruttura cloud',      'Macchine virtuali, storage e reti in modalità IaaS/PaaS.'),
    ('DATI',         'Base di dati',              'Database e archivi informativi.'),
    ('RETE',         'Infrastruttura di rete',    'Reti LAN/WAN, firewall, VPN, apparati di sicurezza perimetrale.'),
    ('OT',           'Sistema OT/ICS',            'Sistemi di controllo industriale: SCADA, PLC, RTU, DCS.'),
    ('IDENTITA',     'Servizio di identità',      'Directory, IAM, autenticazione a più fattori.'),
    ('SITO',         'Sito fisico',               'Locali tecnici, sale server, impianti.')
ON CONFLICT (codice) DO NOTHING;

CREATE TABLE IF NOT EXISTS nis2.classificazione_informazione (
    codice        varchar(30)  PRIMARY KEY,
    denominazione varchar(40)  NOT NULL UNIQUE,
    ordine        smallint     NOT NULL UNIQUE
);
COMMENT ON TABLE  nis2.classificazione_informazione IS 'Livelli di classificazione delle informazioni trattate dall''asset (schema ISO/IEC 27001, controllo 5.12).';
COMMENT ON COLUMN nis2.classificazione_informazione.codice        IS 'Codice del livello (chiave naturale).';
COMMENT ON COLUMN nis2.classificazione_informazione.denominazione IS 'Denominazione del livello.';
COMMENT ON COLUMN nis2.classificazione_informazione.ordine        IS 'Ordinamento crescente per riservatezza.';

INSERT INTO nis2.classificazione_informazione (codice, denominazione, ordine) VALUES
    ('PUBBLICO',       'Pubblico',       1),
    ('INTERNO',        'Uso interno',    2),
    ('RISERVATO',      'Riservato',      3),
    ('STRETTAMENTE_RISERVATO', 'Strettamente riservato', 4)
ON CONFLICT (codice) DO NOTHING;

CREATE TABLE IF NOT EXISTS nis2.tipo_dipendenza_asset (
    codice        varchar(20)  PRIMARY KEY,
    denominazione varchar(80)  NOT NULL UNIQUE
);
COMMENT ON TABLE  nis2.tipo_dipendenza_asset IS 'Natura della dipendenza tecnica tra due asset.';
COMMENT ON COLUMN nis2.tipo_dipendenza_asset.codice        IS 'Codice del tipo di dipendenza (chiave naturale).';
COMMENT ON COLUMN nis2.tipo_dipendenza_asset.denominazione IS 'Descrizione del tipo di dipendenza.';

INSERT INTO nis2.tipo_dipendenza_asset (codice, denominazione) VALUES
    ('ESECUZIONE',     'È ospitato su / viene eseguito su'),
    ('DATI',           'Legge o scrive dati da'),
    ('RETE',           'Raggiunge la rete tramite'),
    ('AUTENTICAZIONE', 'Autentica utenti tramite'),
    ('BACKUP',         'Esegue il backup su'),
    ('MONITORAGGIO',   'È monitorato da')
ON CONFLICT (codice) DO NOTHING;

-- -----------------------------------------------------------------------------
-- Domini per fornitori e dipendenze di terze parti
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS nis2.tipo_fornitura (
    codice        varchar(20)  PRIMARY KEY,
    denominazione varchar(100) NOT NULL UNIQUE,
    fornitura_tic boolean      NOT NULL
);
COMMENT ON TABLE  nis2.tipo_fornitura IS 'Tipologia di fornitura di terza parte; il flag fornitura_tic distingue le forniture di prodotti o servizi TIC.';
COMMENT ON COLUMN nis2.tipo_fornitura.codice        IS 'Codice della tipologia di fornitura (chiave naturale).';
COMMENT ON COLUMN nis2.tipo_fornitura.denominazione IS 'Descrizione della fornitura.';
COMMENT ON COLUMN nis2.tipo_fornitura.fornitura_tic IS 'true se si tratta di prodotto o servizio TIC.';

INSERT INTO nis2.tipo_fornitura (codice, denominazione, fornitura_tic) VALUES
    ('CLOUD_IAAS',     'Infrastruttura cloud (IaaS/PaaS)',              true),
    ('CLOUD_SAAS',     'Applicazione in modalità SaaS',                  true),
    ('SERVIZI_GESTITI','Servizi gestiti (MSP)',                          true),
    ('SICUREZZA_GESTITA','Servizi di sicurezza gestiti (MSSP/SOC)',      true),
    ('CONNETTIVITA',   'Connettività e servizi di telecomunicazione',    true),
    ('DATA_CENTER',    'Housing e servizi di data center',               true),
    ('MANUTENZIONE_OT','Manutenzione e assistenza di sistemi OT/ICS',    true),
    ('SVILUPPO_SW',    'Sviluppo e manutenzione software',               true),
    ('ENERGIA',        'Fornitura di energia elettrica',                 false),
    ('LOGISTICA',      'Logistica e trasporto',                          false)
ON CONFLICT (codice) DO NOTHING;

CREATE TABLE IF NOT EXISTS nis2.criterio_rilevanza (
    codice        varchar(20)  PRIMARY KEY,
    denominazione varchar(80)  NOT NULL UNIQUE,
    descrizione   text         NOT NULL
);
COMMENT ON TABLE  nis2.criterio_rilevanza IS 'Criterio per cui un fornitore è considerato rilevante ai fini della comunicazione all''ACN (Determinazione ACN n. 127437/2026).';
COMMENT ON COLUMN nis2.criterio_rilevanza.codice        IS 'Codice del criterio (chiave naturale).';
COMMENT ON COLUMN nis2.criterio_rilevanza.denominazione IS 'Denominazione del criterio.';
COMMENT ON COLUMN nis2.criterio_rilevanza.descrizione   IS 'Spiegazione del criterio.';

INSERT INTO nis2.criterio_rilevanza (codice, denominazione, descrizione) VALUES
    ('TIC',           'Fornitura TIC',            'Fornitura di prodotti o servizi TIC (es. infrastrutture digitali, servizi gestiti, cloud).'),
    ('NON_FUNGIBILE', 'Fornitura non fungibile',  'Fornitura la cui interruzione avrebbe un impatto significativo sulla capacità di erogare le attività o i servizi NIS.'),
    ('NON_RILEVANTE', 'Non rilevante',            'Dipendenza censita a fini interni ma non comunicata come fornitore rilevante.')
ON CONFLICT (codice) DO NOTHING;

-- -----------------------------------------------------------------------------
-- Ruoli organizzativi
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS nis2.ruolo (
    codice                    varchar(40)  PRIMARY KEY,
    denominazione             varchar(120) NOT NULL UNIQUE,
    unico_per_organizzazione  boolean      NOT NULL,
    richiesto_acn             boolean      NOT NULL,
    descrizione               text         NOT NULL
);
COMMENT ON TABLE  nis2.ruolo IS 'Ruoli organizzativi rilevanti per NIS2, GDPR e governo della sicurezza.';
COMMENT ON COLUMN nis2.ruolo.codice                   IS 'Codice del ruolo (chiave naturale).';
COMMENT ON COLUMN nis2.ruolo.denominazione            IS 'Denominazione del ruolo.';
COMMENT ON COLUMN nis2.ruolo.unico_per_organizzazione IS 'true se in ogni istante può esistere al massimo un titolare del ruolo per organizzazione (verificato da trigger).';
COMMENT ON COLUMN nis2.ruolo.richiesto_acn            IS 'true se il ruolo è comunicato all''ACN tramite la piattaforma digitale e compare nel profilo.';
COMMENT ON COLUMN nis2.ruolo.descrizione              IS 'Funzione del ruolo e riferimento normativo.';

INSERT INTO nis2.ruolo (codice, denominazione, unico_per_organizzazione, richiesto_acn, descrizione) VALUES
    ('RAPPRESENTANTE_LEGALE',   'Rappresentante legale',                  true,  true,  'Legale rappresentante del soggetto NIS.'),
    ('PUNTO_CONTATTO',          'Punto di contatto NIS',                  true,  true,  'Persona che cura l''attuazione del decreto NIS per conto del soggetto e interloquisce con l''ACN.'),
    ('SOSTITUTO_PUNTO_CONTATTO','Sostituto del punto di contatto',        true,  true,  'Sostituisce il punto di contatto in caso di assenza o impedimento.'),
    ('REFERENTE_CSIRT',         'Referente CSIRT',                        false, true,  'Referente per le interlocuzioni con il CSIRT Italia, anche per la notifica degli incidenti.'),
    ('MEMBRO_ORGANO_AMM',       'Membro dell''organo di amministrazione', false, true,  'Componente dell''organo di amministrazione e direzione (art. 23 D.Lgs. 138/2024).'),
    ('PROCURATORE_GENERALE',    'Procuratore generale',                   false, true,  'Procuratore generale del soggetto, da indicare nei dati anagrafici (Det. ACN 127437/2026, art. 16, c. 3, lett. a).'),
    ('CISO',                    'Chief Information Security Officer',     true,  false, 'Responsabile della sicurezza delle informazioni.'),
    ('DPO',                     'Responsabile della protezione dei dati', true,  false, 'Data Protection Officer ai sensi degli artt. 37-39 GDPR.'),
    ('RESPONSABILE_IT',         'Responsabile dei sistemi informativi',   true,  false, 'Responsabile della gestione dei sistemi IT/OT.')
ON CONFLICT (codice) DO NOTHING;

COMMIT;

RESET client_min_messages;
