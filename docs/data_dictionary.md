# Data dictionary – schema `nis2`

Generato automaticamente dal catalogo di PostgreSQL con `tools/genera_data_dictionary.py` il 19/09/2026. Descrizioni = `COMMENT ON` definiti negli script SQL.

Legenda: **PK** chiave primaria · **FK** chiave esterna · **UK** vincolo di unicità · **NN** NOT NULL · CHECK/EXCLUDE = vincoli di dominio.

Le 9 tabelle `*_storico` (organizzazione, sede, persona, assegnazione_ruolo, asset, servizio, fornitore, contratto, dipendenza_fornitore) hanno le stesse colonne della tabella corrente più `valido_al`, `operazione`, `motivo`, `archiviato_da`; chiave primaria `(<tabella>_id, versione)`. Sono descritte in fondo.


## Tabelle di dominio (lookup)


### `nis2.paese`

Dominio dei Paesi (ISO 3166-1 alpha-2); il flag membro_ue individua i trasferimenti extra UE.

Righe nel dataset di test: 11.

| Colonna | Tipo | Chiavi | NN | Default | Descrizione |
|---|---|---|---|---|---|
| `codice` | character(2) | PK | sì |  | Codice ISO 3166-1 alpha-2 (chiave naturale). |
| `denominazione` | character varying(80) | UK | sì |  | Nome del Paese in italiano. |
| `membro_ue` | boolean |  | sì |  | true se il Paese è Stato membro dell'Unione europea. |

**Vincoli**

- `ck_paese_codice`: `CHECK ((codice ~ '^[A-Z]{2}$'::text))`
- `paese_denominazione_key`: `UNIQUE (denominazione)`

**Trigger**: `trg_paese_90_audit`

### `nis2.settore`

Settori NIS con l'allegato del D.Lgs. 138/2024 in cui sono elencati (I = alta criticità, II = altri settori critici).

Righe nel dataset di test: 17.

| Colonna | Tipo | Chiavi | NN | Default | Descrizione |
|---|---|---|---|---|---|
| `codice` | character varying(40) | PK | sì |  | Codice mnemonico del settore (chiave naturale). |
| `denominazione` | character varying(150) | UK | sì |  | Denominazione del settore come da allegato. |
| `allegato` | character varying(3) |  | sì |  | Allegato di riferimento (I, II, III, IV). |
| `modello_categorizzazione_codice` | character varying(20) | FK→modello_categorizzazione |  |  | Modello di categorizzazione applicabile (Det. ACN 155238/2026, art. 2); NULL se da determinare. |

**Vincoli**

- `ck_settore_allegato`: `CHECK (((allegato)::text = ANY ((ARRAY['I'::character varying, 'II'::character varying, 'III'::character varying, 'IV'::character varying])::text[])))`
- `settore_modello_categorizzazione_codice_fkey`: `FOREIGN KEY (modello_categorizzazione_codice) REFERENCES nis2.modello_categorizzazione(codice) ON UPDATE CASCADE ON DELETE RESTRICT`
- `settore_denominazione_key`: `UNIQUE (denominazione)`

**Trigger**: `trg_settore_90_audit`

### `nis2.sottosettore`

Sottosettori NIS. I settori privi di sottosettori hanno un unico sottosettore omonimo, così la catena tipologia -> sottosettore -> settore resta sempre completa (niente dipendenze transitive).

Righe nel dataset di test: 11.

| Colonna | Tipo | Chiavi | NN | Default | Descrizione |
|---|---|---|---|---|---|
| `codice` | character varying(40) | PK | sì |  | Codice mnemonico del sottosettore (chiave naturale). |
| `settore_codice` | character varying(40) | FK→settore, UK | sì |  | Settore di appartenenza (FK settore). |
| `denominazione` | character varying(150) | UK | sì |  | Denominazione del sottosettore. |

**Vincoli**

- `sottosettore_settore_codice_fkey`: `FOREIGN KEY (settore_codice) REFERENCES nis2.settore(codice) ON UPDATE CASCADE ON DELETE RESTRICT`
- `uq_sottosettore_denominazione`: `UNIQUE (settore_codice, denominazione)`

**Trigger**: `trg_sottosettore_90_audit`

### `nis2.tipologia_soggetto`

Tipologia di soggetto prevista dagli allegati (es. produttori di energia elettrica, fornitori di servizi gestiti).

Righe nel dataset di test: 12.

| Colonna | Tipo | Chiavi | NN | Default | Descrizione |
|---|---|---|---|---|---|
| `codice` | character varying(50) | PK | sì |  | Codice mnemonico della tipologia (chiave naturale). |
| `sottosettore_codice` | character varying(40) | FK→sottosettore, UK | sì |  | Sottosettore di appartenenza (FK sottosettore); da esso deriva il settore. |
| `denominazione` | character varying(250) | UK | sì |  | Descrizione della tipologia di soggetto. |

**Vincoli**

- `tipologia_soggetto_sottosettore_codice_fkey`: `FOREIGN KEY (sottosettore_codice) REFERENCES nis2.sottosettore(codice) ON UPDATE CASCADE ON DELETE RESTRICT`
- `uq_tipologia_denominazione`: `UNIQUE (sottosettore_codice, denominazione)`

**Trigger**: `trg_tipologia_soggetto_90_audit`

### `nis2.categoria_soggetto`

Categoria NIS del soggetto: essenziale o importante (art. 6 D.Lgs. 138/2024; art. 3 Direttiva (UE) 2022/2555).

Righe nel dataset di test: 2.

| Colonna | Tipo | Chiavi | NN | Default | Descrizione |
|---|---|---|---|---|---|
| `codice` | character varying(20) | PK | sì |  | Codice della categoria (chiave naturale). |
| `denominazione` | character varying(80) | UK | sì |  | Denominazione della categoria. |
| `descrizione` | text |  | sì |  | Criterio sintetico di attribuzione della categoria. |

**Vincoli**

- `categoria_soggetto_denominazione_key`: `UNIQUE (denominazione)`

**Trigger**: `trg_categoria_soggetto_90_audit`

### `nis2.dimensione_impresa`

Classe dimensionale secondo la Raccomandazione 2003/361/CE (micro, piccola, media, grande impresa).

Righe nel dataset di test: 4.

| Colonna | Tipo | Chiavi | NN | Default | Descrizione |
|---|---|---|---|---|---|
| `codice` | character varying(10) | PK | sì |  | Codice della classe dimensionale (chiave naturale). |
| `denominazione` | character varying(40) | UK | sì |  | Denominazione della classe dimensionale. |
| `ordine` | smallint | UK | sì |  | Ordinamento crescente per dimensione. |

**Vincoli**

- `dimensione_impresa_denominazione_key`: `UNIQUE (denominazione)`
- `dimensione_impresa_ordine_key`: `UNIQUE (ordine)`

**Trigger**: `trg_dimensione_impresa_90_audit`

### `nis2.livello_criticita`

Scala ordinale di criticità (1 = bassa ... 4 = critica). La chiave numerica consente confronti (livello >= 3 = asset critico).

Righe nel dataset di test: 4.

| Colonna | Tipo | Chiavi | NN | Default | Descrizione |
|---|---|---|---|---|---|
| `livello` | smallint | PK | sì |  | Valore ordinale della criticità, da 1 a 4 (chiave naturale). |
| `denominazione` | character varying(20) | UK | sì |  | Etichetta del livello. |
| `descrizione` | text |  | sì |  | Impatto atteso in caso di indisponibilità o compromissione. |

**Vincoli**

- `ck_livello_criticita_range`: `CHECK (((livello >= 1) AND (livello <= 4)))`
- `livello_criticita_denominazione_key`: `UNIQUE (denominazione)`

**Trigger**: `trg_livello_criticita_90_audit`

### `nis2.tipo_asset`

Tipologia di asset (hardware, software, dati, rete, OT, cloud, sito).

Righe nel dataset di test: 9.

| Colonna | Tipo | Chiavi | NN | Default | Descrizione |
|---|---|---|---|---|---|
| `codice` | character varying(20) | PK | sì |  | Codice della tipologia (chiave naturale). |
| `denominazione` | character varying(80) | UK | sì |  | Denominazione della tipologia. |
| `descrizione` | text |  | sì |  | Esempi e perimetro della tipologia. |

**Vincoli**

- `tipo_asset_denominazione_key`: `UNIQUE (denominazione)`

**Trigger**: `trg_tipo_asset_90_audit`

### `nis2.classificazione_informazione`

Livelli di classificazione delle informazioni trattate dall'asset (schema ISO/IEC 27001, controllo 5.12).

Righe nel dataset di test: 4.

| Colonna | Tipo | Chiavi | NN | Default | Descrizione |
|---|---|---|---|---|---|
| `codice` | character varying(30) | PK | sì |  | Codice del livello (chiave naturale). |
| `denominazione` | character varying(40) | UK | sì |  | Denominazione del livello. |
| `ordine` | smallint | UK | sì |  | Ordinamento crescente per riservatezza. |

**Vincoli**

- `classificazione_informazione_denominazione_key`: `UNIQUE (denominazione)`
- `classificazione_informazione_ordine_key`: `UNIQUE (ordine)`

**Trigger**: `trg_classificazione_informazione_90_audit`

### `nis2.tipo_dipendenza_asset`

Natura della dipendenza tecnica tra due asset.

Righe nel dataset di test: 6.

| Colonna | Tipo | Chiavi | NN | Default | Descrizione |
|---|---|---|---|---|---|
| `codice` | character varying(20) | PK | sì |  | Codice del tipo di dipendenza (chiave naturale). |
| `denominazione` | character varying(80) | UK | sì |  | Descrizione del tipo di dipendenza. |

**Vincoli**

- `tipo_dipendenza_asset_denominazione_key`: `UNIQUE (denominazione)`

**Trigger**: `trg_tipo_dipendenza_asset_90_audit`

### `nis2.tipo_fornitura`

Tipologia di fornitura di terza parte; il flag fornitura_tic distingue le forniture di prodotti o servizi TIC.

Righe nel dataset di test: 10.

| Colonna | Tipo | Chiavi | NN | Default | Descrizione |
|---|---|---|---|---|---|
| `codice` | character varying(20) | PK | sì |  | Codice della tipologia di fornitura (chiave naturale). |
| `denominazione` | character varying(100) | UK | sì |  | Descrizione della fornitura. |
| `fornitura_tic` | boolean |  | sì |  | true se si tratta di prodotto o servizio TIC. |

**Vincoli**

- `tipo_fornitura_denominazione_key`: `UNIQUE (denominazione)`

**Trigger**: `trg_tipo_fornitura_90_audit`

### `nis2.criterio_rilevanza`

Criterio per cui un fornitore è considerato rilevante ai fini della comunicazione all'ACN (Determinazione ACN n. 127437/2026).

Righe nel dataset di test: 3.

| Colonna | Tipo | Chiavi | NN | Default | Descrizione |
|---|---|---|---|---|---|
| `codice` | character varying(20) | PK | sì |  | Codice del criterio (chiave naturale). |
| `denominazione` | character varying(80) | UK | sì |  | Denominazione del criterio. |
| `descrizione` | text |  | sì |  | Spiegazione del criterio. |

**Vincoli**

- `criterio_rilevanza_denominazione_key`: `UNIQUE (denominazione)`

**Trigger**: `trg_criterio_rilevanza_90_audit`

### `nis2.ruolo`

Ruoli organizzativi rilevanti per NIS2, GDPR e governo della sicurezza.

Righe nel dataset di test: 9.

| Colonna | Tipo | Chiavi | NN | Default | Descrizione |
|---|---|---|---|---|---|
| `codice` | character varying(40) | PK | sì |  | Codice del ruolo (chiave naturale). |
| `denominazione` | character varying(120) | UK | sì |  | Denominazione del ruolo. |
| `unico_per_organizzazione` | boolean |  | sì |  | true se in ogni istante può esistere al massimo un titolare del ruolo per organizzazione (verificato da trigger). |
| `richiesto_acn` | boolean |  | sì |  | true se il ruolo è comunicato all'ACN tramite la piattaforma digitale e compare nel profilo. |
| `descrizione` | text |  | sì |  | Funzione del ruolo e riferimento normativo. |

**Vincoli**

- `ruolo_denominazione_key`: `UNIQUE (denominazione)`

**Trigger**: `trg_ruolo_90_audit`

## Anagrafiche e responsabilità


### `nis2.organizzazione`

Soggetti NIS (essenziali o importanti) censiti nel registro. Entità storicizzata.

Righe nel dataset di test: 3.

| Colonna | Tipo | Chiavi | NN | Default | Descrizione |
|---|---|---|---|---|---|
| `organizzazione_id` | bigint | PK | sì | IDENTITY ALWAYS | Identificativo surrogato dell'organizzazione. |
| `ragione_sociale` | character varying(200) |  | sì |  | Ragione sociale comprensiva della forma giuridica. |
| `partita_iva` | character(11) | UK | sì |  | Partita IVA italiana (11 cifre, cifra di controllo verificata da fn_piva_valida). |
| `pec` | character varying(254) |  | sì |  | Domicilio digitale (PEC) del soggetto. |
| `telefono` | character varying(20) |  | sì |  | Numero di telefono del soggetto in formato internazionale (Det. ACN 127437/2026, art. 16, c. 3, lett. a). |
| `email_funzionale` | character varying(254) |  | sì |  | Indirizzo di posta elettronica ordinaria funzionale del soggetto (Det. ACN 127437/2026, art. 16, c. 3, lett. a). |
| `sito_web` | character varying(254) |  |  |  | Sito istituzionale (solo https). |
| `tipologia_soggetto_codice` | character varying(50) | FK→tipologia_soggetto | sì |  | Tipologia di soggetto NIS (FK tipologia_soggetto): determina sottosettore e settore. |
| `categoria_soggetto_codice` | character varying(20) | FK→categoria_soggetto | sì |  | Categoria NIS: essenziale o importante (FK categoria_soggetto). |
| `dimensione_codice` | character varying(10) | FK→dimensione_impresa | sì |  | Classe dimensionale dichiarata (FK dimensione_impresa). |
| `numero_dipendenti` | integer |  |  |  | Numero di dipendenti (dato informativo; la classe dimensionale considera anche fatturato e imprese collegate). |
| `versione` | integer |  | sì | 1 | Numero della versione corrente del record (gestito da trigger). |
| `valido_dal` | timestamp with time zone |  | sì | now() | Istante di inizio validità della versione corrente (gestito da trigger). |
| `modificato_da` | character varying(128) |  | sì | SESSION_USER | Utente database autore della versione corrente (gestito da trigger). |

**Vincoli**

- `ck_organizzazione_dipendenti`: `CHECK (((numero_dipendenti IS NULL) OR (numero_dipendenti >= 0)))`
- `ck_organizzazione_email`: `CHECK (nis2.fn_email_valida((email_funzionale)::text))`
- `ck_organizzazione_pec`: `CHECK (nis2.fn_email_valida((pec)::text))`
- `ck_organizzazione_piva`: `CHECK (nis2.fn_piva_valida((partita_iva)::text))`
- `ck_organizzazione_ragione`: `CHECK ((btrim((ragione_sociale)::text) <> ''::text))`
- `ck_organizzazione_sito`: `CHECK (((sito_web IS NULL) OR ((sito_web)::text ~ '^https://[a-z0-9.-]+\.[a-z]{2,}(/.*)?$'::text)))`
- `ck_organizzazione_telefono`: `CHECK (((telefono)::text ~ '^\+[0-9]{2,3}( ?[0-9]{2,4}){2,4}$'::text))`
- `ck_organizzazione_versione`: `CHECK ((versione >= 1))`
- `organizzazione_categoria_soggetto_codice_fkey`: `FOREIGN KEY (categoria_soggetto_codice) REFERENCES nis2.categoria_soggetto(codice) ON UPDATE CASCADE ON DELETE RESTRICT`
- `organizzazione_dimensione_codice_fkey`: `FOREIGN KEY (dimensione_codice) REFERENCES nis2.dimensione_impresa(codice) ON UPDATE CASCADE ON DELETE RESTRICT`
- `organizzazione_tipologia_soggetto_codice_fkey`: `FOREIGN KEY (tipologia_soggetto_codice) REFERENCES nis2.tipologia_soggetto(codice) ON UPDATE CASCADE ON DELETE RESTRICT`
- `uq_organizzazione_partita_iva`: `UNIQUE (partita_iva)`

**Indici secondari**

- `ix_organizzazione_categoria`: `btree (categoria_soggetto_codice)`
- `ix_organizzazione_ragione_sociale`: `btree (lower((ragione_sociale)::text))`
- `ix_organizzazione_tipologia`: `btree (tipologia_soggetto_codice)`

**Trigger**: `trg_organizzazione_10_versione`, `trg_organizzazione_80_storico`, `trg_organizzazione_90_audit`

### `nis2.sede`

Sedi e siti delle organizzazioni (legale, operative, impianti, data center). Entità storicizzata.

Righe nel dataset di test: 10.

| Colonna | Tipo | Chiavi | NN | Default | Descrizione |
|---|---|---|---|---|---|
| `sede_id` | bigint | PK | sì | IDENTITY ALWAYS | Identificativo surrogato della sede. |
| `organizzazione_id` | bigint | FK→organizzazione, UK | sì |  | Organizzazione titolare della sede (FK). |
| `tipo_sede` | character varying(20) |  | sì |  | Tipo di sede: LEGALE, OPERATIVA, PRODUTTIVA, IMPIANTO, DATA_CENTER (una sola sede LEGALE per organizzazione, indice univoco parziale). |
| `denominazione` | character varying(120) | UK | sì |  | Nome breve della sede, univoco nell'organizzazione. |
| `indirizzo` | character varying(200) |  | sì |  | Via/piazza e numero civico. |
| `cap` | character(5) |  | sì |  | Codice di avviamento postale (5 cifre). |
| `comune` | character varying(100) |  | sì |  | Comune. |
| `provincia` | character(2) |  | sì |  | Sigla della provincia (2 lettere maiuscole). |
| `paese_codice` | character(2) | FK→paese | sì | 'IT'::bpchar | Paese della sede (FK paese). |
| `versione` | integer |  | sì | 1 | Numero della versione corrente del record (gestito da trigger). |
| `valido_dal` | timestamp with time zone |  | sì | now() | Istante di inizio validità della versione corrente (gestito da trigger). |
| `modificato_da` | character varying(128) |  | sì | SESSION_USER | Utente database autore della versione corrente (gestito da trigger). |

**Vincoli**

- `ck_sede_cap`: `CHECK ((cap ~ '^[0-9]{5}$'::text))`
- `ck_sede_provincia`: `CHECK ((provincia ~ '^[A-Z]{2}$'::text))`
- `ck_sede_tipo`: `CHECK (((tipo_sede)::text = ANY ((ARRAY['LEGALE'::character varying, 'OPERATIVA'::character varying, 'PRODUTTIVA'::character varying, 'IMPIANTO'::character varying, 'DATA_CENTER'::character varying])::text[])))`
- `ck_sede_versione`: `CHECK ((versione >= 1))`
- `sede_organizzazione_id_fkey`: `FOREIGN KEY (organizzazione_id) REFERENCES nis2.organizzazione(organizzazione_id) ON DELETE RESTRICT`
- `sede_paese_codice_fkey`: `FOREIGN KEY (paese_codice) REFERENCES nis2.paese(codice) ON UPDATE CASCADE ON DELETE RESTRICT`
- `uq_sede_denominazione`: `UNIQUE (organizzazione_id, denominazione)`

**Indici secondari**

- `ix_sede_comune`: `btree (comune)`
- `ux_sede_legale_unica`: `btree (organizzazione_id) WHERE ((tipo_sede)::text = 'LEGALE'::text)`

**Trigger**: `trg_sede_10_versione`, `trg_sede_80_storico`, `trg_sede_90_audit`

### `nis2.persona`

Persone fisiche che ricoprono ruoli o sono proprietarie di asset e servizi (anche esterne all'organizzazione). Minimizzazione GDPR: solo dati di contatto professionali. Entità storicizzata.

Righe nel dataset di test: 20.

| Colonna | Tipo | Chiavi | NN | Default | Descrizione |
|---|---|---|---|---|---|
| `persona_id` | bigint | PK | sì | IDENTITY ALWAYS | Identificativo surrogato della persona. |
| `nome` | character varying(80) |  | sì |  | Nome. |
| `cognome` | character varying(80) |  | sì |  | Cognome. |
| `email` | character varying(254) | UK | sì |  | E-mail professionale, univoca. |
| `telefono` | character varying(20) |  |  |  | Telefono professionale in formato internazionale (+39 ...). |
| `versione` | integer |  | sì | 1 | Numero della versione corrente del record (gestito da trigger). |
| `valido_dal` | timestamp with time zone |  | sì | now() | Istante di inizio validità della versione corrente (gestito da trigger). |
| `modificato_da` | character varying(128) |  | sì | SESSION_USER | Utente database autore della versione corrente (gestito da trigger). |

**Vincoli**

- `ck_persona_email`: `CHECK (nis2.fn_email_valida((email)::text))`
- `ck_persona_nome`: `CHECK (((btrim((nome)::text) <> ''::text) AND (btrim((cognome)::text) <> ''::text)))`
- `ck_persona_telefono`: `CHECK (((telefono IS NULL) OR ((telefono)::text ~ '^\+[0-9]{2,3}( ?[0-9]{2,4}){2,4}$'::text)))`
- `ck_persona_versione`: `CHECK ((versione >= 1))`
- `uq_persona_email`: `UNIQUE (email)`

**Indici secondari**

- `ix_persona_cognome_nome`: `btree (lower((cognome)::text), lower((nome)::text))`
- `ux_persona_email_lower`: `btree (lower((email)::text))`

**Trigger**: `trg_persona_10_versione`, `trg_persona_80_storico`, `trg_persona_90_audit`

### `nis2.assegnazione_ruolo`

Attribuzione di un ruolo a una persona per un'organizzazione con periodo di validità (tempo di validità "di business"). Unicità e incompatibilità verificate da trigger. Entità storicizzata.

Righe nel dataset di test: 29.

| Colonna | Tipo | Chiavi | NN | Default | Descrizione |
|---|---|---|---|---|---|
| `assegnazione_ruolo_id` | bigint | PK | sì | IDENTITY ALWAYS | Identificativo surrogato dell'assegnazione. |
| `organizzazione_id` | bigint | FK→organizzazione, UK | sì |  | Organizzazione per cui il ruolo è ricoperto (FK). |
| `persona_id` | bigint | FK→persona, UK | sì |  | Persona titolare del ruolo (FK). |
| `ruolo_codice` | character varying(40) | FK→ruolo, UK | sì |  | Ruolo ricoperto (FK ruolo). |
| `data_inizio` | date | UK | sì |  | Primo giorno di validità dell'incarico (incluso). |
| `data_fine` | date |  |  |  | Ultimo giorno di validità (incluso); NULL = incarico in corso. |
| `atto_nomina` | character varying(120) |  |  |  | Riferimento all'atto di nomina o delega (es. delibera, procura). |
| `versione` | integer |  | sì | 1 | Numero della versione corrente del record (gestito da trigger). |
| `valido_dal` | timestamp with time zone |  | sì | now() | Istante di inizio validità della versione corrente (gestito da trigger). |
| `modificato_da` | character varying(128) |  | sì | SESSION_USER | Utente database autore della versione corrente (gestito da trigger). |

**Vincoli**

- `ck_assegnazione_date`: `CHECK (((data_fine IS NULL) OR (data_fine >= data_inizio)))`
- `ck_assegnazione_versione`: `CHECK ((versione >= 1))`
- `assegnazione_ruolo_organizzazione_id_fkey`: `FOREIGN KEY (organizzazione_id) REFERENCES nis2.organizzazione(organizzazione_id) ON DELETE RESTRICT`
- `assegnazione_ruolo_persona_id_fkey`: `FOREIGN KEY (persona_id) REFERENCES nis2.persona(persona_id) ON DELETE RESTRICT`
- `assegnazione_ruolo_ruolo_codice_fkey`: `FOREIGN KEY (ruolo_codice) REFERENCES nis2.ruolo(codice) ON UPDATE CASCADE ON DELETE RESTRICT`
- `uq_assegnazione`: `UNIQUE (organizzazione_id, persona_id, ruolo_codice, data_inizio)`

**Indici secondari**

- `ix_assegnazione_in_corso`: `btree (organizzazione_id, ruolo_codice) WHERE (data_fine IS NULL)`
- `ix_assegnazione_org_ruolo_periodo`: `btree (organizzazione_id, ruolo_codice, data_inizio, data_fine)`
- `ix_assegnazione_persona`: `btree (persona_id)`
- `ix_assegnazione_ruolo`: `btree (ruolo_codice)`

**Trigger**: `trg_assegnazione_ruolo_10_versione`, `trg_assegnazione_ruolo_20_regole`, `trg_assegnazione_ruolo_80_storico`, `trg_assegnazione_ruolo_90_audit`

## Asset e servizi


### `nis2.asset`

Asset informativi, tecnologici e fisici dell'organizzazione. Entità storicizzata.

Righe nel dataset di test: 24.

| Colonna | Tipo | Chiavi | NN | Default | Descrizione |
|---|---|---|---|---|---|
| `asset_id` | bigint | PK | sì | IDENTITY ALWAYS | Identificativo surrogato dell'asset. |
| `organizzazione_id` | bigint | FK→organizzazione, UK | sì |  | Organizzazione titolare dell'asset (FK). |
| `codice` | character varying(30) | UK | sì |  | Codice inventariale, univoco nell'organizzazione (maiuscole, cifre e trattini). |
| `denominazione` | character varying(150) |  | sì |  | Nome dell'asset. |
| `descrizione` | text |  |  |  | Descrizione funzionale. |
| `tipo_asset_codice` | character varying(20) | FK→tipo_asset | sì |  | Tipologia dell'asset (FK tipo_asset). |
| `classificazione_codice` | character varying(30) | FK→classificazione_informazione | sì |  | Classificazione delle informazioni trattate (FK classificazione_informazione). |
| `criticita_livello` | smallint | FK→livello_criticita | sì |  | Livello di criticità 1-4 (FK livello_criticita); livello >= 3 = asset critico. |
| `rto_minuti` | integer |  |  |  | Recovery Time Objective in minuti (0-43200); obbligatorio per gli asset critici. |
| `rpo_minuti` | integer |  |  |  | Recovery Point Objective in minuti (0-43200); obbligatorio per gli asset critici. |
| `sede_id` | bigint | FK→sede |  |  | Ubicazione fisica (FK sede, stessa organizzazione); NULL per asset in cloud di terzi. |
| `proprietario_persona_id` | bigint | FK→persona | sì |  | Proprietario (asset owner) responsabile dell'asset (FK persona). |
| `versione` | integer |  | sì | 1 | Numero della versione corrente del record (gestito da trigger). |
| `valido_dal` | timestamp with time zone |  | sì | now() | Istante di inizio validità della versione corrente (gestito da trigger). |
| `modificato_da` | character varying(128) |  | sì | SESSION_USER | Utente database autore della versione corrente (gestito da trigger). |

**Vincoli**

- `ck_asset_codice`: `CHECK (((codice)::text ~ '^[A-Z0-9][A-Z0-9-]{2,29}$'::text))`
- `ck_asset_critico_rto_rpo`: `CHECK (((criticita_livello < 3) OR ((rto_minuti IS NOT NULL) AND (rpo_minuti IS NOT NULL))))`
- `ck_asset_rpo`: `CHECK (((rpo_minuti IS NULL) OR ((rpo_minuti >= 0) AND (rpo_minuti <= 43200))))`
- `ck_asset_rto`: `CHECK (((rto_minuti IS NULL) OR ((rto_minuti >= 0) AND (rto_minuti <= 43200))))`
- `ck_asset_versione`: `CHECK ((versione >= 1))`
- `asset_classificazione_codice_fkey`: `FOREIGN KEY (classificazione_codice) REFERENCES nis2.classificazione_informazione(codice) ON UPDATE CASCADE ON DELETE RESTRICT`
- `asset_criticita_livello_fkey`: `FOREIGN KEY (criticita_livello) REFERENCES nis2.livello_criticita(livello) ON UPDATE CASCADE ON DELETE RESTRICT`
- `asset_organizzazione_id_fkey`: `FOREIGN KEY (organizzazione_id) REFERENCES nis2.organizzazione(organizzazione_id) ON DELETE RESTRICT`
- `asset_proprietario_persona_id_fkey`: `FOREIGN KEY (proprietario_persona_id) REFERENCES nis2.persona(persona_id) ON DELETE RESTRICT`
- `asset_sede_id_fkey`: `FOREIGN KEY (sede_id) REFERENCES nis2.sede(sede_id) ON DELETE RESTRICT`
- `asset_tipo_asset_codice_fkey`: `FOREIGN KEY (tipo_asset_codice) REFERENCES nis2.tipo_asset(codice) ON UPDATE CASCADE ON DELETE RESTRICT`
- `uq_asset_codice`: `UNIQUE (organizzazione_id, codice)`

**Indici secondari**

- `ix_asset_classificazione`: `btree (classificazione_codice)`
- `ix_asset_critici`: `btree (organizzazione_id, criticita_livello DESC) WHERE (criticita_livello >= 3)`
- `ix_asset_proprietario`: `btree (proprietario_persona_id)`
- `ix_asset_sede`: `btree (sede_id)`
- `ix_asset_tipo`: `btree (tipo_asset_codice)`

**Trigger**: `trg_asset_10_versione`, `trg_asset_20_coerenza`, `trg_asset_80_storico`, `trg_asset_90_audit`

### `nis2.servizio`

Attività e servizi svolti o erogati dall'organizzazione, internamente ed esternamente, con perimetro NIS, macro-area e categoria di rilevanza (elenco categorizzato, art. 30 D.Lgs. 138/2024). Entità storicizzata.

Righe nel dataset di test: 10.

| Colonna | Tipo | Chiavi | NN | Default | Descrizione |
|---|---|---|---|---|---|
| `servizio_id` | bigint | PK | sì | IDENTITY ALWAYS | Identificativo surrogato del servizio. |
| `organizzazione_id` | bigint | FK→organizzazione, UK | sì |  | Organizzazione che eroga il servizio (FK). |
| `codice` | character varying(30) | UK | sì |  | Codice del servizio, univoco nell'organizzazione. |
| `denominazione` | character varying(150) |  | sì |  | Nome del servizio. |
| `descrizione` | text |  |  |  | Descrizione del servizio e dei destinatari. |
| `criticita_livello` | smallint | FK→livello_criticita | sì |  | Livello di criticità 1-4 (FK livello_criticita). |
| `utenti_impattati` | integer |  | sì |  | Stima degli utenti o clienti impattati da un'interruzione. |
| `perimetro_nis` | boolean |  | sì | true | true se l'attività o il servizio rientra nel perimetro NIS e va riportato nel profilo ACN. |
| `macro_area_codice` | character varying(30) | FK→macro_area | sì |  | Macro-area del modello di categorizzazione ACN (Det. 155238/2026, art. 3, c. 2, lett. a). |
| `categoria_rilevanza_codice` | character varying(20) | FK→categoria_rilevanza | sì |  | Categoria di rilevanza attribuita (Det. 155238/2026, art. 3, c. 2, lett. c). |
| `valutazione_categoria` | text |  |  |  | Motivazione documentata quando la categoria differisce da quella pre-assegnata alla macro-area (Det. 155238/2026, art. 3, c. 3); obbligatoria in quel caso (trigger). |
| `responsabile_persona_id` | bigint | FK→persona | sì |  | Responsabile del servizio (service owner, FK persona). |
| `versione` | integer |  | sì | 1 | Numero della versione corrente del record (gestito da trigger). |
| `valido_dal` | timestamp with time zone |  | sì | now() | Istante di inizio validità della versione corrente (gestito da trigger). |
| `modificato_da` | character varying(128) |  | sì | SESSION_USER | Utente database autore della versione corrente (gestito da trigger). |

**Vincoli**

- `ck_servizio_codice`: `CHECK (((codice)::text ~ '^[A-Z0-9][A-Z0-9-]{2,29}$'::text))`
- `ck_servizio_utenti`: `CHECK ((utenti_impattati >= 0))`
- `ck_servizio_versione`: `CHECK ((versione >= 1))`
- `servizio_categoria_rilevanza_codice_fkey`: `FOREIGN KEY (categoria_rilevanza_codice) REFERENCES nis2.categoria_rilevanza(codice) ON UPDATE CASCADE ON DELETE RESTRICT`
- `servizio_criticita_livello_fkey`: `FOREIGN KEY (criticita_livello) REFERENCES nis2.livello_criticita(livello) ON UPDATE CASCADE ON DELETE RESTRICT`
- `servizio_macro_area_codice_fkey`: `FOREIGN KEY (macro_area_codice) REFERENCES nis2.macro_area(codice) ON UPDATE CASCADE ON DELETE RESTRICT`
- `servizio_organizzazione_id_fkey`: `FOREIGN KEY (organizzazione_id) REFERENCES nis2.organizzazione(organizzazione_id) ON DELETE RESTRICT`
- `servizio_responsabile_persona_id_fkey`: `FOREIGN KEY (responsabile_persona_id) REFERENCES nis2.persona(persona_id) ON DELETE RESTRICT`
- `uq_servizio_codice`: `UNIQUE (organizzazione_id, codice)`

**Indici secondari**

- `ix_servizio_criticita`: `btree (criticita_livello)`
- `ix_servizio_perimetro_nis`: `btree (organizzazione_id) WHERE perimetro_nis`
- `ix_servizio_responsabile`: `btree (responsabile_persona_id)`

**Trigger**: `trg_servizio_10_versione`, `trg_servizio_20_categoria`, `trg_servizio_80_storico`, `trg_servizio_90_audit`

### `nis2.servizio_paese`

Stati in cui ciascun servizio è erogato (informazione richiesta nell'aggiornamento annuale delle informazioni).

Righe nel dataset di test: 13.

| Colonna | Tipo | Chiavi | NN | Default | Descrizione |
|---|---|---|---|---|---|
| `servizio_id` | bigint | PK, FK→servizio | sì |  | Servizio (FK). |
| `paese_codice` | character(2) | PK, FK→paese | sì |  | Paese di erogazione (FK paese). |

**Vincoli**

- `servizio_paese_paese_codice_fkey`: `FOREIGN KEY (paese_codice) REFERENCES nis2.paese(codice) ON UPDATE CASCADE ON DELETE RESTRICT`
- `servizio_paese_servizio_id_fkey`: `FOREIGN KEY (servizio_id) REFERENCES nis2.servizio(servizio_id) ON DELETE CASCADE`

**Indici secondari**

- `ix_servizio_paese_paese`: `btree (paese_codice)`

**Trigger**: `trg_servizio_paese_90_audit`

### `nis2.servizio_asset`

Associazione molti-a-molti tra servizi e asset che li supportano (stessa organizzazione, verificato da trigger).

Righe nel dataset di test: 31.

| Colonna | Tipo | Chiavi | NN | Default | Descrizione |
|---|---|---|---|---|---|
| `servizio_id` | bigint | PK, FK→servizio | sì |  | Servizio supportato (FK). |
| `asset_id` | bigint | PK, FK→asset | sì |  | Asset di supporto (FK). |
| `ruolo_asset` | character varying(10) |  | sì | 'PRIMARIO'::character varying | PRIMARIO se l'asset è indispensabile al servizio, SUPPORTO se ne è componente ausiliaria. |

**Vincoli**

- `ck_servizio_asset_ruolo`: `CHECK (((ruolo_asset)::text = ANY ((ARRAY['PRIMARIO'::character varying, 'SUPPORTO'::character varying])::text[])))`
- `servizio_asset_asset_id_fkey`: `FOREIGN KEY (asset_id) REFERENCES nis2.asset(asset_id) ON DELETE CASCADE`
- `servizio_asset_servizio_id_fkey`: `FOREIGN KEY (servizio_id) REFERENCES nis2.servizio(servizio_id) ON DELETE CASCADE`

**Indici secondari**

- `ix_servizio_asset_asset`: `btree (asset_id)`

**Trigger**: `trg_servizio_asset_20_coerenza`, `trg_servizio_asset_90_audit`

### `nis2.dipendenza_asset`

Dipendenze tecniche tra asset: asset_id dipende da asset_richiesto_id. Il trigger anti-ciclo mantiene il grafo aciclico.

Righe nel dataset di test: 21.

| Colonna | Tipo | Chiavi | NN | Default | Descrizione |
|---|---|---|---|---|---|
| `asset_id` | bigint | FK→asset, PK | sì |  | Asset dipendente (FK). |
| `asset_richiesto_id` | bigint | FK→asset, PK | sì |  | Asset da cui dipende (FK), diverso dal primo. |
| `tipo_dipendenza_codice` | character varying(20) | FK→tipo_dipendenza_asset | sì |  | Natura della dipendenza (FK tipo_dipendenza_asset). |

**Vincoli**

- `ck_dipendenza_asset_no_self`: `CHECK ((asset_id <> asset_richiesto_id))`
- `dipendenza_asset_asset_id_fkey`: `FOREIGN KEY (asset_id) REFERENCES nis2.asset(asset_id) ON DELETE CASCADE`
- `dipendenza_asset_asset_richiesto_id_fkey`: `FOREIGN KEY (asset_richiesto_id) REFERENCES nis2.asset(asset_id) ON DELETE CASCADE`
- `dipendenza_asset_tipo_dipendenza_codice_fkey`: `FOREIGN KEY (tipo_dipendenza_codice) REFERENCES nis2.tipo_dipendenza_asset(codice) ON UPDATE CASCADE ON DELETE RESTRICT`

**Indici secondari**

- `ix_dipendenza_asset_richiesto`: `btree (asset_richiesto_id)`
- `ix_dipendenza_asset_tipo`: `btree (tipo_dipendenza_codice)`

**Trigger**: `trg_dipendenza_asset_20_coerenza`, `trg_dipendenza_asset_30_aciclica`, `trg_dipendenza_asset_90_audit`

## Terze parti


### `nis2.fornitore`

Terze parti che forniscono prodotti o servizi. Se il fornitore è a sua volta un soggetto censito, organizzazione_id lo collega (supply chain a più livelli). Entità storicizzata.

Righe nel dataset di test: 9.

| Colonna | Tipo | Chiavi | NN | Default | Descrizione |
|---|---|---|---|---|---|
| `fornitore_id` | bigint | PK | sì | IDENTITY ALWAYS | Identificativo surrogato del fornitore. |
| `ragione_sociale` | character varying(200) |  | sì |  | Denominazione del fornitore. |
| `identificativo_fiscale` | character varying(20) | UK | sì |  | Partita IVA (IT, verificata) o identificativo fiscale estero. |
| `paese_codice` | character(2) | FK→paese, UK | sì |  | Paese della sede legale (FK paese). |
| `email_contatto` | character varying(254) |  | sì |  | Contatto di sicurezza del fornitore. |
| `organizzazione_id` | bigint | FK→organizzazione, UK |  |  | Organizzazione del registro che coincide con il fornitore (facoltativa, univoca). |
| `versione` | integer |  | sì | 1 | Numero della versione corrente del record (gestito da trigger). |
| `valido_dal` | timestamp with time zone |  | sì | now() | Istante di inizio validità della versione corrente (gestito da trigger). |
| `modificato_da` | character varying(128) |  | sì | SESSION_USER | Utente database autore della versione corrente (gestito da trigger). |

**Vincoli**

- `ck_fornitore_email`: `CHECK (nis2.fn_email_valida((email_contatto)::text))`
- `ck_fornitore_fiscale_estero`: `CHECK (((paese_codice = 'IT'::bpchar) OR ((identificativo_fiscale)::text ~ '^[A-Z0-9]{5,20}$'::text)))`
- `ck_fornitore_piva_it`: `CHECK (((paese_codice <> 'IT'::bpchar) OR nis2.fn_piva_valida((identificativo_fiscale)::text)))`
- `ck_fornitore_versione`: `CHECK ((versione >= 1))`
- `fornitore_organizzazione_id_fkey`: `FOREIGN KEY (organizzazione_id) REFERENCES nis2.organizzazione(organizzazione_id) ON DELETE SET NULL`
- `fornitore_paese_codice_fkey`: `FOREIGN KEY (paese_codice) REFERENCES nis2.paese(codice) ON UPDATE CASCADE ON DELETE RESTRICT`
- `uq_fornitore_fiscale`: `UNIQUE (paese_codice, identificativo_fiscale)`
- `uq_fornitore_organizzazione`: `UNIQUE (organizzazione_id)`

**Indici secondari**

- `ix_fornitore_paese`: `btree (paese_codice)`
- `ix_fornitore_ragione_sociale`: `btree (lower((ragione_sociale)::text))`

**Trigger**: `trg_fornitore_10_versione`, `trg_fornitore_80_storico`, `trg_fornitore_90_audit`

### `nis2.contratto`

Contratti di fornitura con le garanzie di sicurezza previste (art. 24 D.Lgs. 138/2024, sicurezza della catena di approvvigionamento; art. 28 GDPR). Entità storicizzata.

Righe nel dataset di test: 14.

| Colonna | Tipo | Chiavi | NN | Default | Descrizione |
|---|---|---|---|---|---|
| `contratto_id` | bigint | PK | sì | IDENTITY ALWAYS | Identificativo surrogato del contratto. |
| `organizzazione_id` | bigint | FK→organizzazione, UK | sì |  | Organizzazione committente (FK). |
| `fornitore_id` | bigint | FK→fornitore | sì |  | Fornitore contraente (FK). |
| `codice` | character varying(30) | UK | sì |  | Numero di repertorio del contratto, univoco nell'organizzazione. |
| `oggetto` | character varying(250) |  | sì |  | Oggetto del contratto. |
| `data_inizio` | date |  | sì |  | Data di decorrenza. |
| `data_fine` | date |  |  |  | Data di scadenza; NULL = tempo indeterminato. |
| `clausole_sicurezza` | boolean |  | sì |  | true se il contratto contiene clausole di sicurezza informatica. |
| `dpa_art28` | boolean |  | sì |  | true se è stipulato un accordo sul trattamento dei dati (art. 28 GDPR). |
| `diritto_audit` | boolean |  | sì |  | true se il committente ha diritto di audit sul fornitore. |
| `notifica_incidenti_ore` | integer |  |  |  | Termine contrattuale (ore) entro cui il fornitore notifica gli incidenti; NULL = non previsto. |
| `versione` | integer |  | sì | 1 | Numero della versione corrente del record (gestito da trigger). |
| `valido_dal` | timestamp with time zone |  | sì | now() | Istante di inizio validità della versione corrente (gestito da trigger). |
| `modificato_da` | character varying(128) |  | sì | SESSION_USER | Utente database autore della versione corrente (gestito da trigger). |

**Vincoli**

- `ck_contratto_date`: `CHECK (((data_fine IS NULL) OR (data_fine > data_inizio)))`
- `ck_contratto_notifica`: `CHECK (((notifica_incidenti_ore IS NULL) OR ((notifica_incidenti_ore >= 1) AND (notifica_incidenti_ore <= 720))))`
- `ck_contratto_versione`: `CHECK ((versione >= 1))`
- `contratto_fornitore_id_fkey`: `FOREIGN KEY (fornitore_id) REFERENCES nis2.fornitore(fornitore_id) ON DELETE RESTRICT`
- `contratto_organizzazione_id_fkey`: `FOREIGN KEY (organizzazione_id) REFERENCES nis2.organizzazione(organizzazione_id) ON DELETE RESTRICT`
- `uq_contratto_codice`: `UNIQUE (organizzazione_id, codice)`

**Indici secondari**

- `ix_contratto_fornitore`: `btree (fornitore_id)`
- `ix_contratto_scadenza`: `btree (data_fine) WHERE (data_fine IS NOT NULL)`

**Trigger**: `trg_contratto_10_versione`, `trg_contratto_20_coerenza`, `trg_contratto_80_storico`, `trg_contratto_90_audit`

### `nis2.dipendenza_fornitore`

Dipendenza di un servizio o di un asset da una fornitura di terza parte, regolata da un contratto. Il fornitore si ricava dal contratto (niente dipendenze transitive). Entità storicizzata.

Righe nel dataset di test: 16.

| Colonna | Tipo | Chiavi | NN | Default | Descrizione |
|---|---|---|---|---|---|
| `dipendenza_fornitore_id` | bigint | PK | sì | IDENTITY ALWAYS | Identificativo surrogato della dipendenza. |
| `contratto_id` | bigint | FK→contratto, UK | sì |  | Contratto che regola la fornitura (FK); determina fornitore e committente. |
| `servizio_id` | bigint | FK→servizio, UK |  |  | Servizio dipendente (FK); alternativo ad asset_id. |
| `asset_id` | bigint | FK→asset, UK |  |  | Asset dipendente (FK); alternativo a servizio_id. |
| `tipo_fornitura_codice` | character varying(20) | FK→tipo_fornitura | sì |  | Tipologia di fornitura (FK tipo_fornitura). |
| `criterio_rilevanza_codice` | character varying(20) | FK→criterio_rilevanza | sì |  | Criterio di rilevanza del fornitore: TIC, NON_FUNGIBILE, NON_RILEVANTE (FK criterio_rilevanza). |
| `codice_cpv` | character(10) |  |  |  | Codice CPV (Common Procurement Vocabulary) della fornitura, formato 99999999-9. |
| `criticita_livello` | smallint | FK→livello_criticita | sì |  | Criticità della dipendenza 1-4 (FK livello_criticita). |
| `paese_trattamento_codice` | character(2) | FK→paese |  |  | Paese in cui il fornitore tratta o conserva i dati (FK paese); NULL se non tratta dati. |
| `versione` | integer |  | sì | 1 | Numero della versione corrente del record (gestito da trigger). |
| `valido_dal` | timestamp with time zone |  | sì | now() | Istante di inizio validità della versione corrente (gestito da trigger). |
| `modificato_da` | character varying(128) |  | sì | SESSION_USER | Utente database autore della versione corrente (gestito da trigger). |

**Vincoli**

- `ck_dipendenza_cpv`: `CHECK (((codice_cpv IS NULL) OR (codice_cpv ~ '^[0-9]{8}-[0-9]$'::text)))`
- `ck_dipendenza_oggetto`: `CHECK ((num_nonnulls(servizio_id, asset_id) = 1))`
- `ck_dipendenza_versione`: `CHECK ((versione >= 1))`
- `dipendenza_fornitore_asset_id_fkey`: `FOREIGN KEY (asset_id) REFERENCES nis2.asset(asset_id) ON DELETE CASCADE`
- `dipendenza_fornitore_contratto_id_fkey`: `FOREIGN KEY (contratto_id) REFERENCES nis2.contratto(contratto_id) ON DELETE RESTRICT`
- `dipendenza_fornitore_criterio_rilevanza_codice_fkey`: `FOREIGN KEY (criterio_rilevanza_codice) REFERENCES nis2.criterio_rilevanza(codice) ON UPDATE CASCADE ON DELETE RESTRICT`
- `dipendenza_fornitore_criticita_livello_fkey`: `FOREIGN KEY (criticita_livello) REFERENCES nis2.livello_criticita(livello) ON UPDATE CASCADE ON DELETE RESTRICT`
- `dipendenza_fornitore_paese_trattamento_codice_fkey`: `FOREIGN KEY (paese_trattamento_codice) REFERENCES nis2.paese(codice) ON UPDATE CASCADE ON DELETE RESTRICT`
- `dipendenza_fornitore_servizio_id_fkey`: `FOREIGN KEY (servizio_id) REFERENCES nis2.servizio(servizio_id) ON DELETE CASCADE`
- `dipendenza_fornitore_tipo_fornitura_codice_fkey`: `FOREIGN KEY (tipo_fornitura_codice) REFERENCES nis2.tipo_fornitura(codice) ON UPDATE CASCADE ON DELETE RESTRICT`
- `uq_dipendenza_fornitore`: `UNIQUE NULLS NOT DISTINCT (contratto_id, servizio_id, asset_id)`

**Indici secondari**

- `ix_dipendenza_fornitore_asset`: `btree (asset_id) WHERE (asset_id IS NOT NULL)`
- `ix_dipendenza_fornitore_criterio`: `btree (criterio_rilevanza_codice)`
- `ix_dipendenza_fornitore_paese`: `btree (paese_trattamento_codice)`
- `ix_dipendenza_fornitore_servizio`: `btree (servizio_id) WHERE (servizio_id IS NOT NULL)`
- `ix_dipendenza_fornitore_tipo`: `btree (tipo_fornitura_codice)`

**Trigger**: `trg_dipendenza_fornitore_10_versione`, `trg_dipendenza_fornitore_20_coerenza`, `trg_dipendenza_fornitore_80_storico`, `trg_dipendenza_fornitore_90_audit`

## Perimetro di rete


### `nis2.spazio_ip`

Spazio di indirizzamento IP pubblico in uso o nella disponibilità del soggetto. Il vincolo di esclusione impedisce blocchi sovrapposti.

Righe nel dataset di test: 6.

| Colonna | Tipo | Chiavi | NN | Default | Descrizione |
|---|---|---|---|---|---|
| `spazio_ip_id` | bigint | PK | sì | IDENTITY ALWAYS | Identificativo surrogato del blocco IP. |
| `organizzazione_id` | bigint | FK→organizzazione | sì |  | Organizzazione titolare (FK). |
| `rete` | cidr |  | sì |  | Blocco di indirizzi in notazione CIDR (tipo nativo cidr). |
| `descrizione` | character varying(150) |  | sì |  | Uso del blocco (es. servizi esposti, VPN). |

**Vincoli**

- `spazio_ip_organizzazione_id_fkey`: `FOREIGN KEY (organizzazione_id) REFERENCES nis2.organizzazione(organizzazione_id) ON DELETE CASCADE`
- `ex_spazio_ip_sovrapposto`: `EXCLUDE USING gist (rete inet_ops WITH &&)`

**Indici secondari**

- `ix_spazio_ip_organizzazione`: `btree (organizzazione_id)`

**Trigger**: `trg_spazio_ip_90_audit`

### `nis2.dominio`

Nomi di dominio in uso o nella disponibilità del soggetto.

Righe nel dataset di test: 6.

| Colonna | Tipo | Chiavi | NN | Default | Descrizione |
|---|---|---|---|---|---|
| `dominio_id` | bigint | PK | sì | IDENTITY ALWAYS | Identificativo surrogato del dominio. |
| `organizzazione_id` | bigint | FK→organizzazione | sì |  | Organizzazione titolare (FK). |
| `nome_dominio` | character varying(253) | UK | sì |  | Nome di dominio completo in minuscolo, univoco. |
| `descrizione` | character varying(150) |  | sì |  | Uso del dominio. |

**Vincoli**

- `ck_dominio_nome`: `CHECK (((nome_dominio)::text ~ '^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$'::text))`
- `dominio_organizzazione_id_fkey`: `FOREIGN KEY (organizzazione_id) REFERENCES nis2.organizzazione(organizzazione_id) ON DELETE CASCADE`
- `uq_dominio_nome`: `UNIQUE (nome_dominio)`

**Indici secondari**

- `ix_dominio_organizzazione`: `btree (organizzazione_id)`

**Trigger**: `trg_dominio_90_audit`

## Audit


### `nis2.audit_log`

Registro di audit append-only di tutte le modifiche ai dati dello schema nis2 (chi, cosa, quando, perché).

Righe nel dataset di test: 214.

| Colonna | Tipo | Chiavi | NN | Default | Descrizione |
|---|---|---|---|---|---|
| `audit_log_id` | bigint | PK | sì | IDENTITY ALWAYS | Identificativo progressivo dell'evento. |
| `istante` | timestamp with time zone |  | sì | clock_timestamp() | Istante effettivo della modifica (clock_timestamp). |
| `id_transazione` | bigint |  | sì | ((pg_current_xact_id())::text)::bigint | Identificativo della transazione: raggruppa le modifiche atomiche. |
| `utente` | character varying(128) |  | sì | SESSION_USER | Utente database di sessione che ha eseguito l'operazione. |
| `applicazione` | character varying(128) |  | sì | COALESCE(NULLIF(current_setting('application_name'::text, true), ''::text), 'n/d'::text) | Valore di application_name del client (es. pgAdmin 4, psql). |
| `tabella` | character varying(63) |  | sì |  | Tabella modificata. |
| `operazione` | character(1) |  | sì |  | I = inserimento, U = modifica, D = cancellazione. |
| `chiave` | jsonb |  | sì |  | Chiave della riga interessata in formato JSON. |
| `dati_prima` | jsonb |  |  |  | Immagine della riga prima della modifica (NULL per I). |
| `dati_dopo` | jsonb |  |  |  | Immagine della riga dopo la modifica (NULL per D). |
| `campi_modificati` | text[] |  |  |  | Elenco delle colonne effettivamente variate (solo U). |
| `motivo` | text |  |  |  | Motivo dichiarato con nis2.fn_imposta_motivo (facoltativo). |

**Vincoli**

- `ck_audit_dati`: `CHECK ((((operazione = 'I'::bpchar) AND (dati_prima IS NULL) AND (dati_dopo IS NOT NULL)) OR ((operazione = 'U'::bpchar) AND (dati_prima IS NOT NULL) AND (dati_dopo IS NOT NULL)) OR ((operazione = 'D'::bpchar) AND (dati_prima IS NOT NULL) AND (dati_dopo IS NULL))))`
- `ck_audit_operazione`: `CHECK ((operazione = ANY (ARRAY['I'::bpchar, 'U'::bpchar, 'D'::bpchar])))`

**Indici secondari**

- `ix_audit_log_chiave`: `gin (chiave jsonb_path_ops)`
- `ix_audit_log_istante_brin`: `brin (istante)`
- `ix_audit_log_tabella_istante`: `btree (tabella, istante DESC)`

**Trigger**: `trg_audit_log_immutabile`

## Tabelle di storico

| Tabella | Colonne aggiuntive | Chiave primaria | Righe nel dataset |
|---|---|---|---|
| `nis2.assegnazione_ruolo_storico` | valido_al, operazione (U/D), motivo, archiviato_da | (assegnazione_ruolo_id, versione) | 1 |
| `nis2.asset_storico` | valido_al, operazione (U/D), motivo, archiviato_da | (asset_id, versione) | 1 |
| `nis2.contratto_storico` | valido_al, operazione (U/D), motivo, archiviato_da | (contratto_id, versione) | 0 |
| `nis2.dipendenza_fornitore_storico` | valido_al, operazione (U/D), motivo, archiviato_da | (dipendenza_fornitore_id, versione) | 0 |
| `nis2.fornitore_storico` | valido_al, operazione (U/D), motivo, archiviato_da | (fornitore_id, versione) | 0 |
| `nis2.organizzazione_storico` | valido_al, operazione (U/D), motivo, archiviato_da | (organizzazione_id, versione) | 0 |
| `nis2.persona_storico` | valido_al, operazione (U/D), motivo, archiviato_da | (persona_id, versione) | 0 |
| `nis2.sede_storico` | valido_al, operazione (U/D), motivo, archiviato_da | (sede_id, versione) | 0 |
| `nis2.servizio_storico` | valido_al, operazione (U/D), motivo, archiviato_da | (servizio_id, versione) | 0 |

## Viste, funzioni e procedure

| Oggetto | Tipo | Descrizione |
|---|---|---|
| `nis2.v_asset_critici` | vista | Asset con criticità ALTA o CRITICA, con RTO/RPO, ubicazione, proprietario e numero di servizi supportati. |
| `nis2.v_categorizzazione_attivita` | vista | Elenco categorizzato delle attività e dei servizi (art. 30 D.Lgs. 138/2024; Det. ACN 155238/2026): macro-area, categoria pre-assegnata e attribuita, scostamento e valutazione. |
| `nis2.v_dipendenze_terze_parti` | vista | Dipendenze di servizi e asset da fornitori terzi, con criterio di rilevanza, codice CPV, garanzie contrattuali e Paese di trattamento dei dati. |
| `nis2.v_organizzazione` | vista | Anagrafica delle organizzazioni con classificazione NIS completa (settore, sottosettore, tipologia, categoria) e sede legale. |
| `nis2.v_profilo_acn` | vista | Profilo ACN di tutte le organizzazioni in formato tabellare a colonne fisse (campi minimi), una riga per elemento, raggruppato in 8 sezioni (compreso l'elenco categorizzato delle attività e dei servizi). |
| `nis2.v_punti_contatto` | vista | Punti di contatto e responsabilità comunicati all'ACN (punto di contatto, sostituto, referenti CSIRT, rappresentante legale, organi di amministrazione) in corso alla data odierna. |
| `nis2.v_ruoli_attivi` | vista | Incarichi in corso alla data odierna, per organizzazione e ruolo. |
| `nis2.v_servizi_erogati` | vista | Servizi erogati con criticità, utenti impattati, Stati di erogazione, asset collegati e dipendenze dirette da terzi. |
| `nis2.fn_asset_alla_data(bigint,timestamp with time zone)` | funzione | Stato di un asset a una data, con la stessa struttura della tabella nis2.asset (vuoto se non esisteva). |
| `nis2.fn_email_valida(text)` | funzione | Verifica sintattica di un indirizzo e-mail (parte locale, dominio, TLD di almeno 2 lettere). |
| `nis2.fn_impatto_asset(bigint)` | funzione | Analisi d'impatto: elenca asset e servizi che dipendono direttamente o indirettamente dall'asset indicato, con la distanza nel grafo. |
| `nis2.fn_imposta_motivo(text)` | funzione | Imposta il motivo delle modifiche per la transazione corrente (SET LOCAL); viene registrato in storico e audit. |
| `nis2.fn_motivo_corrente()` | funzione | Restituisce il motivo impostato per la transazione corrente, o NULL. |
| `nis2.fn_piano_asset_critici(integer,bigint)` | funzione | Diagnostica: restituisce il piano EXPLAIN ANALYZE della ricerca degli asset critici dopo aver inserito asset sintetici in una sottotransazione poi annullata (il database non viene modificato). |
| `nis2.fn_piva_valida(text)` | funzione | Restituisce true se la stringa è una partita IVA italiana formalmente valida (11 cifre e cifra di controllo corretta). Usata nei vincoli CHECK. |
| `nis2.fn_profilo_acn(bigint)` | funzione | Restituisce il profilo ACN (campi minimi) dell'organizzazione indicata, ordinato per sezione; errore NIS07 se l'organizzazione non esiste. |
| `nis2.fn_profilo_acn_csv(bigint,text)` | funzione | Restituisce il profilo ACN dell'organizzazione come testo CSV conforme a RFC 4180 (intestazione, virgolette dove servono, CRLF). Separatore , (default) o ; per Excel in italiano. |
| `nis2.fn_record_alla_data(text,bigint,timestamp with time zone)` | funzione | Restituisce in JSONB lo stato del record p_id della tabella storicizzata p_tabella all'istante p_istante (NULL se non esisteva). |
| `nis2.fn_trg_assegnazione_regole()` | funzione | Trigger BEFORE INSERT/UPDATE su assegnazione_ruolo: un solo titolare per i ruoli unici in periodi sovrapposti; punto di contatto e sostituto devono essere persone diverse. |
| `nis2.fn_trg_audit()` | funzione | Trigger AFTER INSERT/UPDATE/DELETE generico: registra ogni modifica in nis2.audit_log in formato JSONB. |
| `nis2.fn_trg_coerenza_organizzazione()` | funzione | Trigger BEFORE INSERT/UPDATE: verifica che le entità collegate appartengano alla stessa organizzazione (sede-asset, servizio-asset, asset-asset, contratto-oggetto) e che nessuno sia fornitore di sé stesso. |
| `nis2.fn_trg_dipendenza_asset_aciclica()` | funzione | Trigger BEFORE INSERT/UPDATE su dipendenza_asset: rifiuta gli archi che chiuderebbero un ciclo (visita ricorsiva del grafo). |
| `nis2.fn_trg_immutabile()` | funzione | Trigger BEFORE UPDATE/DELETE che rende immutabili storico e audit log. |
| `nis2.fn_trg_servizio_categoria()` | funzione | Trigger BEFORE INSERT/UPDATE su servizio: se la categoria di rilevanza differisce da quella pre-assegnata alla macro-area nel modello del soggetto, richiede la valutazione documentata (Det. ACN 155238/2026, art. 3, c. 3). |
| `nis2.fn_trg_storico()` | funzione | Trigger AFTER UPDATE/DELETE: copia la versione superata nella tabella <nome>_storico con intervallo di validità, operazione e motivo. |
| `nis2.fn_trg_versione()` | funzione | Trigger BEFORE INSERT/UPDATE: imposta versione, valido_dal e modificato_da; blocca la modifica della PK; ignora gli UPDATE senza variazioni. |
| `nis2.sp_sostituisci_titolare_ruolo(bigint,character varying,bigint,date,text,character varying)` | procedura | Sostituisce in modo atomico il titolare di un ruolo: chiude l'incarico in corso al giorno precedente la decorrenza e crea il nuovo, registrando il motivo in storico e audit. |
