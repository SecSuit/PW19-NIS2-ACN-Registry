-- =============================================================================
-- PW19 - Registro NIS2/ACN
-- File      : 03_tabelle.sql
-- Scopo     : tabelle principali (anagrafiche, asset e servizi, dipendenze,
--             perimetro di rete) con PK, FK, NOT NULL, UNIQUE e CHECK.
-- Dipende da: 02_lookup.sql
-- Idempotenza: CREATE TABLE IF NOT EXISTS
--
-- Convenzioni
--  * chiave primaria surrogata <tabella>_id GENERATED ALWAYS AS IDENTITY
--    (le tabelle ponte usano la chiave composta delle due FK);
--  * colonne di versioning sulle entità storicizzate:
--      versione       numero progressivo della versione corrente (parte da 1)
--      valido_dal     istante da cui la versione corrente è valida
--      modificato_da  utente database che ha prodotto la versione corrente
--    i valori sono imposti dai trigger di 05_trigger_versioning.sql;
--  * politica ON DELETE:
--      RESTRICT sulle entità di registro (un'organizzazione, una persona o un
--               fornitore non si cancellano finché hanno elementi collegati:
--               si evita la perdita silenziosa di informazioni di conformità);
--      CASCADE  sulle tabelle ponte e di dettaglio che non hanno significato
--               senza il padre (es. servizio_asset, dominio);
--    ON UPDATE CASCADE solo verso le lookup con chiave naturale; le chiavi
--    surrogate non sono modificabili (identity ALWAYS + trigger di blocco).
-- =============================================================================

SET client_encoding = 'UTF8';
SET client_min_messages = warning;

BEGIN;

-- -----------------------------------------------------------------------------
-- ORGANIZZAZIONE: soggetto NIS censito nel registro
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS nis2.organizzazione (
    organizzazione_id          bigint       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ragione_sociale            varchar(200) NOT NULL,
    partita_iva                char(11)     NOT NULL,
    pec                        varchar(254) NOT NULL,
    telefono                   varchar(20)  NOT NULL,
    email_funzionale           varchar(254) NOT NULL,
    sito_web                   varchar(254),
    tipologia_soggetto_codice  varchar(50)  NOT NULL
        REFERENCES nis2.tipologia_soggetto (codice) ON UPDATE CASCADE ON DELETE RESTRICT,
    categoria_soggetto_codice  varchar(20)  NOT NULL
        REFERENCES nis2.categoria_soggetto (codice) ON UPDATE CASCADE ON DELETE RESTRICT,
    dimensione_codice          varchar(10)  NOT NULL
        REFERENCES nis2.dimensione_impresa (codice) ON UPDATE CASCADE ON DELETE RESTRICT,
    numero_dipendenti          integer,
    versione                   integer      NOT NULL DEFAULT 1,
    valido_dal                 timestamptz  NOT NULL DEFAULT now(),
    modificato_da              varchar(128) NOT NULL DEFAULT session_user,
    CONSTRAINT uq_organizzazione_partita_iva UNIQUE (partita_iva),
    CONSTRAINT ck_organizzazione_piva        CHECK (nis2.fn_piva_valida(partita_iva)),
    CONSTRAINT ck_organizzazione_pec         CHECK (nis2.fn_email_valida(pec)),
    CONSTRAINT ck_organizzazione_telefono    CHECK (telefono ~ '^\+[0-9]{2,3}( ?[0-9]{2,4}){2,4}$'),
    CONSTRAINT ck_organizzazione_email       CHECK (nis2.fn_email_valida(email_funzionale)),
    CONSTRAINT ck_organizzazione_sito        CHECK (sito_web IS NULL OR sito_web ~ '^https://[a-z0-9.-]+\.[a-z]{2,}(/.*)?$'),
    CONSTRAINT ck_organizzazione_dipendenti  CHECK (numero_dipendenti IS NULL OR numero_dipendenti >= 0),
    CONSTRAINT ck_organizzazione_versione    CHECK (versione >= 1),
    CONSTRAINT ck_organizzazione_ragione     CHECK (btrim(ragione_sociale) <> '')
);
COMMENT ON TABLE  nis2.organizzazione IS 'Soggetti NIS (essenziali o importanti) censiti nel registro. Entità storicizzata.';
COMMENT ON COLUMN nis2.organizzazione.organizzazione_id         IS 'Identificativo surrogato dell''organizzazione.';
COMMENT ON COLUMN nis2.organizzazione.ragione_sociale           IS 'Ragione sociale comprensiva della forma giuridica.';
COMMENT ON COLUMN nis2.organizzazione.partita_iva               IS 'Partita IVA italiana (11 cifre, cifra di controllo verificata da fn_piva_valida).';
COMMENT ON COLUMN nis2.organizzazione.pec                       IS 'Domicilio digitale (PEC) del soggetto.';
COMMENT ON COLUMN nis2.organizzazione.telefono                  IS 'Numero di telefono del soggetto in formato internazionale (Det. ACN 127437/2026, art. 16, c. 3, lett. a).';
COMMENT ON COLUMN nis2.organizzazione.email_funzionale          IS 'Indirizzo di posta elettronica ordinaria funzionale del soggetto (Det. ACN 127437/2026, art. 16, c. 3, lett. a).';
COMMENT ON COLUMN nis2.organizzazione.sito_web                  IS 'Sito istituzionale (solo https).';
COMMENT ON COLUMN nis2.organizzazione.tipologia_soggetto_codice IS 'Tipologia di soggetto NIS (FK tipologia_soggetto): determina sottosettore e settore.';
COMMENT ON COLUMN nis2.organizzazione.categoria_soggetto_codice IS 'Categoria NIS: essenziale o importante (FK categoria_soggetto).';
COMMENT ON COLUMN nis2.organizzazione.dimensione_codice         IS 'Classe dimensionale dichiarata (FK dimensione_impresa).';
COMMENT ON COLUMN nis2.organizzazione.numero_dipendenti         IS 'Numero di dipendenti (dato informativo; la classe dimensionale considera anche fatturato e imprese collegate).';
COMMENT ON COLUMN nis2.organizzazione.versione                  IS 'Numero della versione corrente del record (gestito da trigger).';
COMMENT ON COLUMN nis2.organizzazione.valido_dal                IS 'Istante di inizio validità della versione corrente (gestito da trigger).';
COMMENT ON COLUMN nis2.organizzazione.modificato_da             IS 'Utente database autore della versione corrente (gestito da trigger).';

-- -----------------------------------------------------------------------------
-- SEDE
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS nis2.sede (
    sede_id            bigint       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    organizzazione_id  bigint       NOT NULL
        REFERENCES nis2.organizzazione (organizzazione_id) ON DELETE RESTRICT,
    tipo_sede          varchar(20)  NOT NULL,
    denominazione      varchar(120) NOT NULL,
    indirizzo          varchar(200) NOT NULL,
    cap                char(5)      NOT NULL,
    comune             varchar(100) NOT NULL,
    provincia          char(2)      NOT NULL,
    paese_codice       char(2)      NOT NULL DEFAULT 'IT'
        REFERENCES nis2.paese (codice) ON UPDATE CASCADE ON DELETE RESTRICT,
    versione           integer      NOT NULL DEFAULT 1,
    valido_dal         timestamptz  NOT NULL DEFAULT now(),
    modificato_da      varchar(128) NOT NULL DEFAULT session_user,
    CONSTRAINT uq_sede_denominazione UNIQUE (organizzazione_id, denominazione),
    CONSTRAINT ck_sede_tipo          CHECK (tipo_sede IN ('LEGALE', 'OPERATIVA', 'PRODUTTIVA', 'IMPIANTO', 'DATA_CENTER')),
    CONSTRAINT ck_sede_cap           CHECK (cap ~ '^[0-9]{5}$'),
    CONSTRAINT ck_sede_provincia     CHECK (provincia ~ '^[A-Z]{2}$'),
    CONSTRAINT ck_sede_versione      CHECK (versione >= 1)
);
COMMENT ON TABLE  nis2.sede IS 'Sedi e siti delle organizzazioni (legale, operative, impianti, data center). Entità storicizzata.';
COMMENT ON COLUMN nis2.sede.sede_id           IS 'Identificativo surrogato della sede.';
COMMENT ON COLUMN nis2.sede.organizzazione_id IS 'Organizzazione titolare della sede (FK).';
COMMENT ON COLUMN nis2.sede.tipo_sede         IS 'Tipo di sede: LEGALE, OPERATIVA, PRODUTTIVA, IMPIANTO, DATA_CENTER (una sola sede LEGALE per organizzazione, indice univoco parziale).';
COMMENT ON COLUMN nis2.sede.denominazione     IS 'Nome breve della sede, univoco nell''organizzazione.';
COMMENT ON COLUMN nis2.sede.indirizzo         IS 'Via/piazza e numero civico.';
COMMENT ON COLUMN nis2.sede.cap               IS 'Codice di avviamento postale (5 cifre).';
COMMENT ON COLUMN nis2.sede.comune            IS 'Comune.';
COMMENT ON COLUMN nis2.sede.provincia         IS 'Sigla della provincia (2 lettere maiuscole).';
COMMENT ON COLUMN nis2.sede.paese_codice      IS 'Paese della sede (FK paese).';
COMMENT ON COLUMN nis2.sede.versione          IS 'Numero della versione corrente del record (gestito da trigger).';
COMMENT ON COLUMN nis2.sede.valido_dal        IS 'Istante di inizio validità della versione corrente (gestito da trigger).';
COMMENT ON COLUMN nis2.sede.modificato_da     IS 'Utente database autore della versione corrente (gestito da trigger).';

-- -----------------------------------------------------------------------------
-- PERSONA e ASSEGNAZIONE_RUOLO
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS nis2.persona (
    persona_id     bigint       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nome           varchar(80)  NOT NULL,
    cognome        varchar(80)  NOT NULL,
    email          varchar(254) NOT NULL,
    telefono       varchar(20),
    versione       integer      NOT NULL DEFAULT 1,
    valido_dal     timestamptz  NOT NULL DEFAULT now(),
    modificato_da  varchar(128) NOT NULL DEFAULT session_user,
    CONSTRAINT uq_persona_email     UNIQUE (email),
    CONSTRAINT ck_persona_email     CHECK (nis2.fn_email_valida(email)),
    CONSTRAINT ck_persona_telefono  CHECK (telefono IS NULL OR telefono ~ '^\+[0-9]{2,3}( ?[0-9]{2,4}){2,4}$'),
    CONSTRAINT ck_persona_nome      CHECK (btrim(nome) <> '' AND btrim(cognome) <> ''),
    CONSTRAINT ck_persona_versione  CHECK (versione >= 1)
);
COMMENT ON TABLE  nis2.persona IS 'Persone fisiche che ricoprono ruoli o sono proprietarie di asset e servizi (anche esterne all''organizzazione). Minimizzazione GDPR: solo dati di contatto professionali. Entità storicizzata.';
COMMENT ON COLUMN nis2.persona.persona_id    IS 'Identificativo surrogato della persona.';
COMMENT ON COLUMN nis2.persona.nome          IS 'Nome.';
COMMENT ON COLUMN nis2.persona.cognome       IS 'Cognome.';
COMMENT ON COLUMN nis2.persona.email         IS 'E-mail professionale, univoca.';
COMMENT ON COLUMN nis2.persona.telefono      IS 'Telefono professionale in formato internazionale (+39 ...).';
COMMENT ON COLUMN nis2.persona.versione      IS 'Numero della versione corrente del record (gestito da trigger).';
COMMENT ON COLUMN nis2.persona.valido_dal    IS 'Istante di inizio validità della versione corrente (gestito da trigger).';
COMMENT ON COLUMN nis2.persona.modificato_da IS 'Utente database autore della versione corrente (gestito da trigger).';

CREATE TABLE IF NOT EXISTS nis2.assegnazione_ruolo (
    assegnazione_ruolo_id  bigint       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    organizzazione_id      bigint       NOT NULL
        REFERENCES nis2.organizzazione (organizzazione_id) ON DELETE RESTRICT,
    persona_id             bigint       NOT NULL
        REFERENCES nis2.persona (persona_id) ON DELETE RESTRICT,
    ruolo_codice           varchar(40)  NOT NULL
        REFERENCES nis2.ruolo (codice) ON UPDATE CASCADE ON DELETE RESTRICT,
    data_inizio            date         NOT NULL,
    data_fine              date,
    atto_nomina            varchar(120),
    versione               integer      NOT NULL DEFAULT 1,
    valido_dal             timestamptz  NOT NULL DEFAULT now(),
    modificato_da          varchar(128) NOT NULL DEFAULT session_user,
    CONSTRAINT ck_assegnazione_date     CHECK (data_fine IS NULL OR data_fine >= data_inizio),
    CONSTRAINT ck_assegnazione_versione CHECK (versione >= 1),
    CONSTRAINT uq_assegnazione          UNIQUE (organizzazione_id, persona_id, ruolo_codice, data_inizio)
);
COMMENT ON TABLE  nis2.assegnazione_ruolo IS 'Attribuzione di un ruolo a una persona per un''organizzazione con periodo di validità (tempo di validità "di business"). Unicità e incompatibilità verificate da trigger. Entità storicizzata.';
COMMENT ON COLUMN nis2.assegnazione_ruolo.assegnazione_ruolo_id IS 'Identificativo surrogato dell''assegnazione.';
COMMENT ON COLUMN nis2.assegnazione_ruolo.organizzazione_id     IS 'Organizzazione per cui il ruolo è ricoperto (FK).';
COMMENT ON COLUMN nis2.assegnazione_ruolo.persona_id            IS 'Persona titolare del ruolo (FK).';
COMMENT ON COLUMN nis2.assegnazione_ruolo.ruolo_codice          IS 'Ruolo ricoperto (FK ruolo).';
COMMENT ON COLUMN nis2.assegnazione_ruolo.data_inizio           IS 'Primo giorno di validità dell''incarico (incluso).';
COMMENT ON COLUMN nis2.assegnazione_ruolo.data_fine             IS 'Ultimo giorno di validità (incluso); NULL = incarico in corso.';
COMMENT ON COLUMN nis2.assegnazione_ruolo.atto_nomina           IS 'Riferimento all''atto di nomina o delega (es. delibera, procura).';
COMMENT ON COLUMN nis2.assegnazione_ruolo.versione              IS 'Numero della versione corrente del record (gestito da trigger).';
COMMENT ON COLUMN nis2.assegnazione_ruolo.valido_dal            IS 'Istante di inizio validità della versione corrente (gestito da trigger).';
COMMENT ON COLUMN nis2.assegnazione_ruolo.modificato_da         IS 'Utente database autore della versione corrente (gestito da trigger).';

-- -----------------------------------------------------------------------------
-- ASSET
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS nis2.asset (
    asset_id                bigint       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    organizzazione_id       bigint       NOT NULL
        REFERENCES nis2.organizzazione (organizzazione_id) ON DELETE RESTRICT,
    codice                  varchar(30)  NOT NULL,
    denominazione           varchar(150) NOT NULL,
    descrizione             text,
    tipo_asset_codice       varchar(20)  NOT NULL
        REFERENCES nis2.tipo_asset (codice) ON UPDATE CASCADE ON DELETE RESTRICT,
    classificazione_codice  varchar(30)  NOT NULL
        REFERENCES nis2.classificazione_informazione (codice) ON UPDATE CASCADE ON DELETE RESTRICT,
    criticita_livello       smallint     NOT NULL
        REFERENCES nis2.livello_criticita (livello) ON UPDATE CASCADE ON DELETE RESTRICT,
    rto_minuti              integer,
    rpo_minuti              integer,
    sede_id                 bigint
        REFERENCES nis2.sede (sede_id) ON DELETE RESTRICT,
    proprietario_persona_id bigint       NOT NULL
        REFERENCES nis2.persona (persona_id) ON DELETE RESTRICT,
    versione                integer      NOT NULL DEFAULT 1,
    valido_dal              timestamptz  NOT NULL DEFAULT now(),
    modificato_da           varchar(128) NOT NULL DEFAULT session_user,
    CONSTRAINT uq_asset_codice      UNIQUE (organizzazione_id, codice),
    CONSTRAINT ck_asset_codice      CHECK (codice ~ '^[A-Z0-9][A-Z0-9-]{2,29}$'),
    CONSTRAINT ck_asset_rto         CHECK (rto_minuti IS NULL OR rto_minuti BETWEEN 0 AND 43200),
    CONSTRAINT ck_asset_rpo         CHECK (rpo_minuti IS NULL OR rpo_minuti BETWEEN 0 AND 43200),
    CONSTRAINT ck_asset_critico_rto_rpo CHECK (criticita_livello < 3 OR (rto_minuti IS NOT NULL AND rpo_minuti IS NOT NULL)),
    CONSTRAINT ck_asset_versione    CHECK (versione >= 1)
);
COMMENT ON TABLE  nis2.asset IS 'Asset informativi, tecnologici e fisici dell''organizzazione. Entità storicizzata.';
COMMENT ON COLUMN nis2.asset.asset_id                IS 'Identificativo surrogato dell''asset.';
COMMENT ON COLUMN nis2.asset.organizzazione_id       IS 'Organizzazione titolare dell''asset (FK).';
COMMENT ON COLUMN nis2.asset.codice                  IS 'Codice inventariale, univoco nell''organizzazione (maiuscole, cifre e trattini).';
COMMENT ON COLUMN nis2.asset.denominazione           IS 'Nome dell''asset.';
COMMENT ON COLUMN nis2.asset.descrizione             IS 'Descrizione funzionale.';
COMMENT ON COLUMN nis2.asset.tipo_asset_codice       IS 'Tipologia dell''asset (FK tipo_asset).';
COMMENT ON COLUMN nis2.asset.classificazione_codice  IS 'Classificazione delle informazioni trattate (FK classificazione_informazione).';
COMMENT ON COLUMN nis2.asset.criticita_livello       IS 'Livello di criticità 1-4 (FK livello_criticita); livello >= 3 = asset critico.';
COMMENT ON COLUMN nis2.asset.rto_minuti              IS 'Recovery Time Objective in minuti (0-43200); obbligatorio per gli asset critici.';
COMMENT ON COLUMN nis2.asset.rpo_minuti              IS 'Recovery Point Objective in minuti (0-43200); obbligatorio per gli asset critici.';
COMMENT ON COLUMN nis2.asset.sede_id                 IS 'Ubicazione fisica (FK sede, stessa organizzazione); NULL per asset in cloud di terzi.';
COMMENT ON COLUMN nis2.asset.proprietario_persona_id IS 'Proprietario (asset owner) responsabile dell''asset (FK persona).';
COMMENT ON COLUMN nis2.asset.versione                IS 'Numero della versione corrente del record (gestito da trigger).';
COMMENT ON COLUMN nis2.asset.valido_dal              IS 'Istante di inizio validità della versione corrente (gestito da trigger).';
COMMENT ON COLUMN nis2.asset.modificato_da           IS 'Utente database autore della versione corrente (gestito da trigger).';

-- -----------------------------------------------------------------------------
-- SERVIZIO
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS nis2.servizio (
    servizio_id                bigint       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    organizzazione_id          bigint       NOT NULL
        REFERENCES nis2.organizzazione (organizzazione_id) ON DELETE RESTRICT,
    codice                     varchar(30)  NOT NULL,
    denominazione              varchar(150) NOT NULL,
    descrizione                text,
    criticita_livello          smallint     NOT NULL
        REFERENCES nis2.livello_criticita (livello) ON UPDATE CASCADE ON DELETE RESTRICT,
    utenti_impattati           integer      NOT NULL,
    perimetro_nis              boolean      NOT NULL DEFAULT true,
    macro_area_codice          varchar(30)  NOT NULL
        REFERENCES nis2.macro_area (codice) ON UPDATE CASCADE ON DELETE RESTRICT,
    categoria_rilevanza_codice varchar(20)  NOT NULL
        REFERENCES nis2.categoria_rilevanza (codice) ON UPDATE CASCADE ON DELETE RESTRICT,
    valutazione_categoria      text,
    responsabile_persona_id    bigint       NOT NULL
        REFERENCES nis2.persona (persona_id) ON DELETE RESTRICT,
    versione                   integer      NOT NULL DEFAULT 1,
    valido_dal                 timestamptz  NOT NULL DEFAULT now(),
    modificato_da              varchar(128) NOT NULL DEFAULT session_user,
    CONSTRAINT uq_servizio_codice   UNIQUE (organizzazione_id, codice),
    CONSTRAINT ck_servizio_codice   CHECK (codice ~ '^[A-Z0-9][A-Z0-9-]{2,29}$'),
    CONSTRAINT ck_servizio_utenti   CHECK (utenti_impattati >= 0),
    CONSTRAINT ck_servizio_versione CHECK (versione >= 1)
);
COMMENT ON TABLE  nis2.servizio IS 'Attività e servizi svolti o erogati dall''organizzazione, internamente ed esternamente, con perimetro NIS, macro-area e categoria di rilevanza (elenco categorizzato, art. 30 D.Lgs. 138/2024). Entità storicizzata.';
COMMENT ON COLUMN nis2.servizio.servizio_id             IS 'Identificativo surrogato del servizio.';
COMMENT ON COLUMN nis2.servizio.organizzazione_id       IS 'Organizzazione che eroga il servizio (FK).';
COMMENT ON COLUMN nis2.servizio.codice                  IS 'Codice del servizio, univoco nell''organizzazione.';
COMMENT ON COLUMN nis2.servizio.denominazione           IS 'Nome del servizio.';
COMMENT ON COLUMN nis2.servizio.descrizione             IS 'Descrizione del servizio e dei destinatari.';
COMMENT ON COLUMN nis2.servizio.criticita_livello       IS 'Livello di criticità 1-4 (FK livello_criticita).';
COMMENT ON COLUMN nis2.servizio.utenti_impattati        IS 'Stima degli utenti o clienti impattati da un''interruzione.';
COMMENT ON COLUMN nis2.servizio.perimetro_nis           IS 'true se l''attività o il servizio rientra nel perimetro NIS e va riportato nel profilo ACN.';
COMMENT ON COLUMN nis2.servizio.macro_area_codice       IS 'Macro-area del modello di categorizzazione ACN (Det. 155238/2026, art. 3, c. 2, lett. a).';
COMMENT ON COLUMN nis2.servizio.categoria_rilevanza_codice IS 'Categoria di rilevanza attribuita (Det. 155238/2026, art. 3, c. 2, lett. c).';
COMMENT ON COLUMN nis2.servizio.valutazione_categoria   IS 'Motivazione documentata quando la categoria differisce da quella pre-assegnata alla macro-area (Det. 155238/2026, art. 3, c. 3); obbligatoria in quel caso (trigger).';
COMMENT ON COLUMN nis2.servizio.responsabile_persona_id IS 'Responsabile del servizio (service owner, FK persona).';
COMMENT ON COLUMN nis2.servizio.versione                IS 'Numero della versione corrente del record (gestito da trigger).';
COMMENT ON COLUMN nis2.servizio.valido_dal              IS 'Istante di inizio validità della versione corrente (gestito da trigger).';
COMMENT ON COLUMN nis2.servizio.modificato_da           IS 'Utente database autore della versione corrente (gestito da trigger).';

CREATE TABLE IF NOT EXISTS nis2.servizio_paese (
    servizio_id   bigint  NOT NULL
        REFERENCES nis2.servizio (servizio_id) ON DELETE CASCADE,
    paese_codice  char(2) NOT NULL
        REFERENCES nis2.paese (codice) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT pk_servizio_paese PRIMARY KEY (servizio_id, paese_codice)
);
COMMENT ON TABLE  nis2.servizio_paese IS 'Stati in cui ciascun servizio è erogato (informazione richiesta nell''aggiornamento annuale delle informazioni).';
COMMENT ON COLUMN nis2.servizio_paese.servizio_id  IS 'Servizio (FK).';
COMMENT ON COLUMN nis2.servizio_paese.paese_codice IS 'Paese di erogazione (FK paese).';

CREATE TABLE IF NOT EXISTS nis2.servizio_asset (
    servizio_id  bigint      NOT NULL
        REFERENCES nis2.servizio (servizio_id) ON DELETE CASCADE,
    asset_id     bigint      NOT NULL
        REFERENCES nis2.asset (asset_id) ON DELETE CASCADE,
    ruolo_asset  varchar(10) NOT NULL DEFAULT 'PRIMARIO',
    CONSTRAINT pk_servizio_asset PRIMARY KEY (servizio_id, asset_id),
    CONSTRAINT ck_servizio_asset_ruolo CHECK (ruolo_asset IN ('PRIMARIO', 'SUPPORTO'))
);
COMMENT ON TABLE  nis2.servizio_asset IS 'Associazione molti-a-molti tra servizi e asset che li supportano (stessa organizzazione, verificato da trigger).';
COMMENT ON COLUMN nis2.servizio_asset.servizio_id IS 'Servizio supportato (FK).';
COMMENT ON COLUMN nis2.servizio_asset.asset_id    IS 'Asset di supporto (FK).';
COMMENT ON COLUMN nis2.servizio_asset.ruolo_asset IS 'PRIMARIO se l''asset è indispensabile al servizio, SUPPORTO se ne è componente ausiliaria.';

-- -----------------------------------------------------------------------------
-- DIPENDENZA_ASSET: grafo orientato aciclico asset -> asset
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS nis2.dipendenza_asset (
    asset_id              bigint      NOT NULL
        REFERENCES nis2.asset (asset_id) ON DELETE CASCADE,
    asset_richiesto_id    bigint      NOT NULL
        REFERENCES nis2.asset (asset_id) ON DELETE CASCADE,
    tipo_dipendenza_codice varchar(20) NOT NULL
        REFERENCES nis2.tipo_dipendenza_asset (codice) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT pk_dipendenza_asset PRIMARY KEY (asset_id, asset_richiesto_id),
    CONSTRAINT ck_dipendenza_asset_no_self CHECK (asset_id <> asset_richiesto_id)
);
COMMENT ON TABLE  nis2.dipendenza_asset IS 'Dipendenze tecniche tra asset: asset_id dipende da asset_richiesto_id. Il trigger anti-ciclo mantiene il grafo aciclico.';
COMMENT ON COLUMN nis2.dipendenza_asset.asset_id               IS 'Asset dipendente (FK).';
COMMENT ON COLUMN nis2.dipendenza_asset.asset_richiesto_id     IS 'Asset da cui dipende (FK), diverso dal primo.';
COMMENT ON COLUMN nis2.dipendenza_asset.tipo_dipendenza_codice IS 'Natura della dipendenza (FK tipo_dipendenza_asset).';

-- -----------------------------------------------------------------------------
-- FORNITORE, CONTRATTO, DIPENDENZA_FORNITORE
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS nis2.fornitore (
    fornitore_id           bigint       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ragione_sociale        varchar(200) NOT NULL,
    identificativo_fiscale varchar(20)  NOT NULL,
    paese_codice           char(2)      NOT NULL
        REFERENCES nis2.paese (codice) ON UPDATE CASCADE ON DELETE RESTRICT,
    email_contatto         varchar(254) NOT NULL,
    organizzazione_id      bigint
        REFERENCES nis2.organizzazione (organizzazione_id) ON DELETE SET NULL,
    versione               integer      NOT NULL DEFAULT 1,
    valido_dal             timestamptz  NOT NULL DEFAULT now(),
    modificato_da          varchar(128) NOT NULL DEFAULT session_user,
    CONSTRAINT uq_fornitore_fiscale       UNIQUE (paese_codice, identificativo_fiscale),
    CONSTRAINT uq_fornitore_organizzazione UNIQUE (organizzazione_id),
    CONSTRAINT ck_fornitore_piva_it       CHECK (paese_codice <> 'IT' OR nis2.fn_piva_valida(identificativo_fiscale)),
    CONSTRAINT ck_fornitore_fiscale_estero CHECK (paese_codice = 'IT' OR identificativo_fiscale ~ '^[A-Z0-9]{5,20}$'),
    CONSTRAINT ck_fornitore_email         CHECK (nis2.fn_email_valida(email_contatto)),
    CONSTRAINT ck_fornitore_versione      CHECK (versione >= 1)
);
COMMENT ON TABLE  nis2.fornitore IS 'Terze parti che forniscono prodotti o servizi. Se il fornitore è a sua volta un soggetto censito, organizzazione_id lo collega (supply chain a più livelli). Entità storicizzata.';
COMMENT ON COLUMN nis2.fornitore.fornitore_id           IS 'Identificativo surrogato del fornitore.';
COMMENT ON COLUMN nis2.fornitore.ragione_sociale        IS 'Denominazione del fornitore.';
COMMENT ON COLUMN nis2.fornitore.identificativo_fiscale IS 'Partita IVA (IT, verificata) o identificativo fiscale estero.';
COMMENT ON COLUMN nis2.fornitore.paese_codice           IS 'Paese della sede legale (FK paese).';
COMMENT ON COLUMN nis2.fornitore.email_contatto         IS 'Contatto di sicurezza del fornitore.';
COMMENT ON COLUMN nis2.fornitore.organizzazione_id      IS 'Organizzazione del registro che coincide con il fornitore (facoltativa, univoca).';
COMMENT ON COLUMN nis2.fornitore.versione               IS 'Numero della versione corrente del record (gestito da trigger).';
COMMENT ON COLUMN nis2.fornitore.valido_dal             IS 'Istante di inizio validità della versione corrente (gestito da trigger).';
COMMENT ON COLUMN nis2.fornitore.modificato_da          IS 'Utente database autore della versione corrente (gestito da trigger).';

CREATE TABLE IF NOT EXISTS nis2.contratto (
    contratto_id              bigint       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    organizzazione_id         bigint       NOT NULL
        REFERENCES nis2.organizzazione (organizzazione_id) ON DELETE RESTRICT,
    fornitore_id              bigint       NOT NULL
        REFERENCES nis2.fornitore (fornitore_id) ON DELETE RESTRICT,
    codice                    varchar(30)  NOT NULL,
    oggetto                   varchar(250) NOT NULL,
    data_inizio               date         NOT NULL,
    data_fine                 date,
    clausole_sicurezza        boolean      NOT NULL,
    dpa_art28                 boolean      NOT NULL,
    diritto_audit             boolean      NOT NULL,
    notifica_incidenti_ore    integer,
    versione                  integer      NOT NULL DEFAULT 1,
    valido_dal                timestamptz  NOT NULL DEFAULT now(),
    modificato_da             varchar(128) NOT NULL DEFAULT session_user,
    CONSTRAINT uq_contratto_codice   UNIQUE (organizzazione_id, codice),
    CONSTRAINT ck_contratto_date     CHECK (data_fine IS NULL OR data_fine > data_inizio),
    CONSTRAINT ck_contratto_notifica CHECK (notifica_incidenti_ore IS NULL OR notifica_incidenti_ore BETWEEN 1 AND 720),
    CONSTRAINT ck_contratto_versione CHECK (versione >= 1)
);
COMMENT ON TABLE  nis2.contratto IS 'Contratti di fornitura con le garanzie di sicurezza previste (art. 24 D.Lgs. 138/2024, sicurezza della catena di approvvigionamento; art. 28 GDPR). Entità storicizzata.';
COMMENT ON COLUMN nis2.contratto.contratto_id           IS 'Identificativo surrogato del contratto.';
COMMENT ON COLUMN nis2.contratto.organizzazione_id      IS 'Organizzazione committente (FK).';
COMMENT ON COLUMN nis2.contratto.fornitore_id           IS 'Fornitore contraente (FK).';
COMMENT ON COLUMN nis2.contratto.codice                 IS 'Numero di repertorio del contratto, univoco nell''organizzazione.';
COMMENT ON COLUMN nis2.contratto.oggetto                IS 'Oggetto del contratto.';
COMMENT ON COLUMN nis2.contratto.data_inizio            IS 'Data di decorrenza.';
COMMENT ON COLUMN nis2.contratto.data_fine              IS 'Data di scadenza; NULL = tempo indeterminato.';
COMMENT ON COLUMN nis2.contratto.clausole_sicurezza     IS 'true se il contratto contiene clausole di sicurezza informatica.';
COMMENT ON COLUMN nis2.contratto.dpa_art28              IS 'true se è stipulato un accordo sul trattamento dei dati (art. 28 GDPR).';
COMMENT ON COLUMN nis2.contratto.diritto_audit          IS 'true se il committente ha diritto di audit sul fornitore.';
COMMENT ON COLUMN nis2.contratto.notifica_incidenti_ore IS 'Termine contrattuale (ore) entro cui il fornitore notifica gli incidenti; NULL = non previsto.';
COMMENT ON COLUMN nis2.contratto.versione               IS 'Numero della versione corrente del record (gestito da trigger).';
COMMENT ON COLUMN nis2.contratto.valido_dal             IS 'Istante di inizio validità della versione corrente (gestito da trigger).';
COMMENT ON COLUMN nis2.contratto.modificato_da          IS 'Utente database autore della versione corrente (gestito da trigger).';

CREATE TABLE IF NOT EXISTS nis2.dipendenza_fornitore (
    dipendenza_fornitore_id   bigint       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    contratto_id              bigint       NOT NULL
        REFERENCES nis2.contratto (contratto_id) ON DELETE RESTRICT,
    servizio_id               bigint
        REFERENCES nis2.servizio (servizio_id) ON DELETE CASCADE,
    asset_id                  bigint
        REFERENCES nis2.asset (asset_id) ON DELETE CASCADE,
    tipo_fornitura_codice     varchar(20)  NOT NULL
        REFERENCES nis2.tipo_fornitura (codice) ON UPDATE CASCADE ON DELETE RESTRICT,
    criterio_rilevanza_codice varchar(20)  NOT NULL
        REFERENCES nis2.criterio_rilevanza (codice) ON UPDATE CASCADE ON DELETE RESTRICT,
    codice_cpv                char(10),
    criticita_livello         smallint     NOT NULL
        REFERENCES nis2.livello_criticita (livello) ON UPDATE CASCADE ON DELETE RESTRICT,
    paese_trattamento_codice  char(2)
        REFERENCES nis2.paese (codice) ON UPDATE CASCADE ON DELETE RESTRICT,
    versione                  integer      NOT NULL DEFAULT 1,
    valido_dal                timestamptz  NOT NULL DEFAULT now(),
    modificato_da             varchar(128) NOT NULL DEFAULT session_user,
    CONSTRAINT ck_dipendenza_oggetto   CHECK (num_nonnulls(servizio_id, asset_id) = 1),
    CONSTRAINT ck_dipendenza_cpv       CHECK (codice_cpv IS NULL OR codice_cpv ~ '^[0-9]{8}-[0-9]$'),
    CONSTRAINT ck_dipendenza_versione  CHECK (versione >= 1),
    CONSTRAINT uq_dipendenza_fornitore UNIQUE NULLS NOT DISTINCT (contratto_id, servizio_id, asset_id)
);
COMMENT ON TABLE  nis2.dipendenza_fornitore IS 'Dipendenza di un servizio o di un asset da una fornitura di terza parte, regolata da un contratto. Il fornitore si ricava dal contratto (niente dipendenze transitive). Entità storicizzata.';
COMMENT ON COLUMN nis2.dipendenza_fornitore.dipendenza_fornitore_id   IS 'Identificativo surrogato della dipendenza.';
COMMENT ON COLUMN nis2.dipendenza_fornitore.contratto_id              IS 'Contratto che regola la fornitura (FK); determina fornitore e committente.';
COMMENT ON COLUMN nis2.dipendenza_fornitore.servizio_id               IS 'Servizio dipendente (FK); alternativo ad asset_id.';
COMMENT ON COLUMN nis2.dipendenza_fornitore.asset_id                  IS 'Asset dipendente (FK); alternativo a servizio_id.';
COMMENT ON COLUMN nis2.dipendenza_fornitore.tipo_fornitura_codice     IS 'Tipologia di fornitura (FK tipo_fornitura).';
COMMENT ON COLUMN nis2.dipendenza_fornitore.criterio_rilevanza_codice IS 'Criterio di rilevanza del fornitore: TIC, NON_FUNGIBILE, NON_RILEVANTE (FK criterio_rilevanza).';
COMMENT ON COLUMN nis2.dipendenza_fornitore.codice_cpv                IS 'Codice CPV (Common Procurement Vocabulary) della fornitura, formato 99999999-9.';
COMMENT ON COLUMN nis2.dipendenza_fornitore.criticita_livello         IS 'Criticità della dipendenza 1-4 (FK livello_criticita).';
COMMENT ON COLUMN nis2.dipendenza_fornitore.paese_trattamento_codice  IS 'Paese in cui il fornitore tratta o conserva i dati (FK paese); NULL se non tratta dati.';
COMMENT ON COLUMN nis2.dipendenza_fornitore.versione                  IS 'Numero della versione corrente del record (gestito da trigger).';
COMMENT ON COLUMN nis2.dipendenza_fornitore.valido_dal                IS 'Istante di inizio validità della versione corrente (gestito da trigger).';
COMMENT ON COLUMN nis2.dipendenza_fornitore.modificato_da             IS 'Utente database autore della versione corrente (gestito da trigger).';

-- -----------------------------------------------------------------------------
-- PERIMETRO DI RETE: spazio di indirizzamento IP pubblico e nomi di dominio
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS nis2.spazio_ip (
    spazio_ip_id       bigint       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    organizzazione_id  bigint       NOT NULL
        REFERENCES nis2.organizzazione (organizzazione_id) ON DELETE CASCADE,
    rete               cidr         NOT NULL,
    descrizione        varchar(150) NOT NULL,
    CONSTRAINT ex_spazio_ip_sovrapposto EXCLUDE USING gist (rete inet_ops WITH &&)
);
COMMENT ON TABLE  nis2.spazio_ip IS 'Spazio di indirizzamento IP pubblico in uso o nella disponibilità del soggetto. Il vincolo di esclusione impedisce blocchi sovrapposti.';
COMMENT ON COLUMN nis2.spazio_ip.spazio_ip_id      IS 'Identificativo surrogato del blocco IP.';
COMMENT ON COLUMN nis2.spazio_ip.organizzazione_id IS 'Organizzazione titolare (FK).';
COMMENT ON COLUMN nis2.spazio_ip.rete              IS 'Blocco di indirizzi in notazione CIDR (tipo nativo cidr).';
COMMENT ON COLUMN nis2.spazio_ip.descrizione       IS 'Uso del blocco (es. servizi esposti, VPN).';

CREATE TABLE IF NOT EXISTS nis2.dominio (
    dominio_id         bigint       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    organizzazione_id  bigint       NOT NULL
        REFERENCES nis2.organizzazione (organizzazione_id) ON DELETE CASCADE,
    nome_dominio       varchar(253) NOT NULL,
    descrizione        varchar(150) NOT NULL,
    CONSTRAINT uq_dominio_nome UNIQUE (nome_dominio),
    CONSTRAINT ck_dominio_nome CHECK (nome_dominio ~ '^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$')
);
COMMENT ON TABLE  nis2.dominio IS 'Nomi di dominio in uso o nella disponibilità del soggetto.';
COMMENT ON COLUMN nis2.dominio.dominio_id        IS 'Identificativo surrogato del dominio.';
COMMENT ON COLUMN nis2.dominio.organizzazione_id IS 'Organizzazione titolare (FK).';
COMMENT ON COLUMN nis2.dominio.nome_dominio      IS 'Nome di dominio completo in minuscolo, univoco.';
COMMENT ON COLUMN nis2.dominio.descrizione       IS 'Uso del dominio.';

COMMIT;

RESET client_min_messages;
