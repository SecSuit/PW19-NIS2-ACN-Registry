# PW19 – Registro NIS2/ACN

**Base dati relazionale in PostgreSQL per catalogare asset, servizi, dipendenze e responsabilità utili alla compilazione dei profili richiesti dall'Agenzia per la Cybersicurezza Nazionale (ACN) nell'ambito della Direttiva (UE) 2022/2555 (NIS2) e del D.Lgs. 138/2024.**

Project Work – CdS Informatica per le Aziende Digitali (L-31), Università Telematica Pegaso
Tema n. 2 *Privacy e sicurezza aziendale* – Traccia PW 19
Autrice: Alfonsina Rocio Perez

> La relazione del Project Work è consegnata tramite la piattaforma dell'Ateneo e non è pubblicata in questo repository (la cartella `relazione/` è esclusa dal controllo di versione). Il repository contiene tutti i deliverable tecnici richiesti dalla traccia: script SQL e schema, query ed export CSV, documentazione tecnica, script di test e dataset simulato.

---

## Cosa fa

Il registro sostituisce fogli di calcolo e documenti sparsi con un'unica base dati normalizzata (3NF/BCNF) che:

- censisce **organizzazioni** NIS (essenziali/importanti), sedi, persone e **ruoli** con periodo di validità (punto di contatto, sostituto, referenti CSIRT, organi di amministrazione, procuratori, CISO, DPO…);
- cataloga **asset** (tipo, classificazione, criticità, RTO/RPO, ubicazione, proprietario) e **servizi** (criticità, utenti impattati, Stati di erogazione, perimetro NIS);
- modella le **dipendenze** asset→asset (grafo aciclico garantito da trigger) e servizio/asset→**fornitore** tramite contratto (criterio di rilevanza, CPV, clausole di sicurezza, DPA, Paese di trattamento);
- mantiene **versioning, storico** (tabelle `*_storico`) e **audit log** generale, con funzioni per ricostruire lo stato di un record a una data;
- supporta l'**elencazione e categorizzazione delle attività e dei servizi** (art. 30; Det. ACN 155238/2026): macro-area, categoria di rilevanza pre-assegnata e attribuita, scostamenti motivati;
- genera il **profilo ACN** (vista `v_profilo_acn`, funzione `fn_profilo_acn`) ed esporta in **CSV**;
- applica il **minimo privilegio** con tre ruoli di accesso (`nis2_lettura`, `nis2_redattore`, `nis2_revisore`) e registra **versione dello schema e cronologia dei deploy** (schema `nis2_meta`).

## Requisiti

| Componente | Versione / impostazione |
|---|---|
| Sistema operativo | Windows 10/11 (testato anche su Linux) |
| PostgreSQL | 18 (sviluppato e verificato su **18.3**) |
| pgAdmin 4 | versione recente, con **Query Tool** e **PSQL Tool** |
| Estensioni PostgreSQL | **nessuna** (solo funzionalità native: PL/pgSQL, JSONB, `cidr`/GiST, range di date) |
| Codifica | database **UTF8**; tutti i file sono UTF-8 senza BOM con fine riga LF |
| Nome del database | **`nis2_acn`** |

## Deploy da zero su Windows con pgAdmin 4

Negli esempi il repository si trova in `C:/PW19-NIS2-ACN-Registry` (per esempio dopo `git clone https://github.com/secsuit/PW19-NIS2-ACN-Registry.git` eseguito in `C:\`). Se si trova altrove, sostituire il percorso nei comandi `\i`, usando sempre le barre `/` anche su Windows.

### 1. Pulizia e creazione del database

1. In pgAdmin, nell'albero a sinistra, selezionare il database **`postgres`** e aprire **Tools → Query Tool**. Bisogna essere collegati a `postgres`, perché non si può eliminare il database a cui si è collegati.
2. Eseguire **da solo** (selezionare la riga e premere F5) il comando che elimina un eventuale database precedente con lo stesso nome:
   ```sql
   DROP DATABASE IF EXISTS nis2_acn WITH (FORCE);
   ```
3. Eseguire **da solo**:
   ```sql
   CREATE DATABASE nis2_acn ENCODING 'UTF8' TEMPLATE template0;
   ```
   I due comandi vanno eseguiti separatamente: se vengono eseguiti insieme, pgAdmin li invia in un'unica transazione e PostgreSQL risponde `cannot run inside a transaction block`.
4. Premere **F5** sull'albero (o tasto destro su *Databases → Refresh*) per vedere `nis2_acn`.

### 2. Deploy degli script

1. Tasto destro su **`nis2_acn` → PSQL Tool**.
2. Incollare ed eseguire:
   ```
   \i 'C:/PW19-NIS2-ACN-Registry/sql/00_run_all.sql'
   ```
   `00_run_all.sql` imposta `ON_ERROR_STOP` e la codifica UTF-8, poi richiama gli script da `01_` a `07_` e `09_` con `\ir` (percorsi relativi al file). Per questo la cartella di lavoro del PSQL Tool non conta.
3. Al termine compare il riepilogo:

   | oggetto | numero |
   |---|---|
   | tabelle | 41 |
   | viste | 8 |
   | funzioni e procedure | 19 |
   | trigger | 67 |
   | indici | 118 |
   | organizzazioni (dati di test) | 3 |
   | righe del profilo ACN | 85 |

Subito prima compare il messaggio `Verifica dei permessi superata`, e subito dopo la tabella con la versione dello schema (`v1.0`) e gli ultimi deploy registrati.

Gli script sono idempotenti: rilanciando `00_run_all.sql` si ottiene lo stesso risultato (il registro dei deploy aggiunge una riga a ogni esecuzione).

### 3. Esecuzione dei test

Sempre nel PSQL Tool:
```
\i 'C:/PW19-NIS2-ACN-Registry/tests/test_integrita_e_versioning.sql'
```
Esito atteso (dopo pochi secondi): `=== ESITO: 56 PASS, 0 FAIL su 56 test (il ROLLBACK finale lascia il database invariato) ===`. I test girano in una transazione annullata, quindi il database non cambia.

Lo stesso file si può aprire anche nel Query Tool ed eseguire con F5: gli esiti compaiono nella scheda *Messages*, il riepilogo nella griglia.

### 4. Query del profilo ACN ed export CSV

- `sql/08_query_profilo_acn.sql` (Query Tool) contiene le query per azienda: asset critici, servizi, dipendenze, punti di contatto, profilo completo.
- **Export da Query Tool:** eseguire `SELECT * FROM nis2.fn_profilo_acn(1);` e premere il pulsante **Save results to file** (freccia verso il basso sopra la griglia, oppure F8). Il file .csv finisce nella cartella Download.
- **Export da PSQL Tool (`\copy`, lato client):**
  ```
  \i 'C:/PW19-NIS2-ACN-Registry/export/esporta_profili_csv.sql'
  ```
  Lo script scrive i CSV di tutte le aziende nella cartella `export/`. Se il repository si trova altrove, prima dello script si indica la cartella con `\set cartella 'C:/percorso/del/repository/export'`.
- Non si usa `COPY ... TO 'percorso'` lato server: il servizio PostgreSQL su Windows non ha i permessi per scrivere nella cartella Documenti dell'utente.

### 5. Query per le figure

`sql/screenshot_query.sql` contiene i blocchi dimostrativi S02–S16 e S18, eseguibili uno alla volta nel Query Tool. La relazione ne riporta una selezione: Figura 2 = S03 (versioning), Figura 3 = S07 (vincolo CHECK), Figura 4 = S09 (indici), Figura 5 = S18 (controllo degli accessi), Figura 6 = S12 (dipendenze da terzi), Figura 7 = S16 (export CSV); la Figura 1 è il diagramma ER e la Figura 8 l'esito dei test.

## Uso rapido

```sql
SELECT * FROM nis2.v_asset_critici;             -- asset critici di tutte le aziende
SELECT * FROM nis2.v_dipendenze_terze_parti;    -- supply chain
SELECT * FROM nis2.v_punti_contatto;            -- punti di contatto in carica
SELECT * FROM nis2.v_categorizzazione_attivita; -- elenco categorizzato (Det. ACN 155238/2026)
SELECT * FROM nis2.fn_profilo_acn(1);           -- profilo ACN di un'azienda
SELECT nis2.fn_profilo_acn_csv(1, ';');         -- profilo come testo CSV (Excel in italiano)
SELECT * FROM nis2.fn_piano_asset_critici();    -- piano di esecuzione con l'indice parziale
```

## Struttura del repository

```
PW19-NIS2-ACN-Registry/
├── README.md                     questo file
├── LICENSE                       licenza MIT
├── .gitignore / .gitattributes   esclusioni (compresa relazione/) e fine riga LF
├── sql/
│   ├── 00_run_all.sql            deploy completo nell'ordine corretto (PSQL Tool)
│   ├── 01_schema.sql             schema dedicato nis2
│   ├── 02_lookup.sql             funzioni di validazione e 17 tabelle di dominio
│   ├── 03_tabelle.sql            14 tabelle principali con PK/FK/UNIQUE/CHECK/EXCLUDE
│   ├── 04_indici.sql             indici su FK, di ricerca e parziali
│   ├── 05_trigger_versioning.sql versioning, storico, audit, regole, stato a una data
│   ├── 06_funzioni_viste.sql     viste tematiche, profilo ACN, CSV, analisi d'impatto, diagnostica
│   ├── 07_dati_test.sql          dataset simulato (3 aziende siciliane fittizie)
│   ├── 08_query_profilo_acn.sql  query del profilo per azienda e istruzioni di export
│   ├── 09_sicurezza_versione.sql ruoli di accesso (minimo privilegio) e versione dello schema
│   └── screenshot_query.sql      blocchi S02–S16 e S18 per le figure della relazione
├── tests/
│   └── test_integrita_e_versioning.sql   56 test automatici PASS/FAIL
├── export/                       CSV di esempio e script \copy
├── docs/
│   ├── er_diagram.png / .mmd     diagramma ER (Mermaid)
│   ├── data_dictionary.md        dizionario dati generato dal catalogo
│   └── guida_popolamento_manutenzione.md
└── tools/
    └── genera_data_dictionary.py rigenera il data dictionary dal database
```

## Versioning degli script

- Ogni fase di sviluppo corrisponde a un commit con un messaggio descrittivo. La versione consegnata è marcata con il tag `v1.0`.
- La versione è registrata anche **nel database**: `09_sicurezza_versione.sql` crea lo schema `nis2_meta` con `versione_schema` (una riga per release, uguale al tag Git) e `registro_deploy` (una riga per ogni esecuzione, con data, utente, database e versione del server). `nis2_meta` non viene cancellato dal deploy, quindi conserva la cronologia.
- Per consultare la versione installata: `SELECT * FROM nis2_meta.registro_deploy ORDER BY deploy_id DESC;`
- Una nuova release (es. `v1.1`) aggiunge la propria riga in `versione_schema`, aggiorna la versione registrata in `09_sicurezza_versione.sql` e viene marcata con il tag Git corrispondente.
- Gli script sono **idempotenti**: `00_run_all.sql` ricrea lo schema da zero. I singoli file usano `IF NOT EXISTS`, `CREATE OR REPLACE` e `ON CONFLICT` e si possono rieseguire.
- Dopo ogni modifica allo schema si rigenera il dizionario dati: `python tools/genera_data_dictionary.py "dbname=nis2_acn user=postgres"` (richiede `psql` nel PATH).

## Controllo degli accessi

`09_sicurezza_versione.sql` revoca ogni permesso a `PUBLIC` e crea tre ruoli senza login, da assegnare agli utenti reali con `GRANT nis2_redattore TO nome_utente;`:

| Ruolo | Può | Non può |
|---|---|---|
| `nis2_lettura` | leggere tabelle e viste, generare profilo e CSV | modificare dati, leggere l'audit log |
| `nis2_redattore` | quanto sopra + inserire, modificare e cancellare nelle 14 tabelle del registro | modificare domini, storico e audit log; eseguire `TRUNCATE` |
| `nis2_revisore` | quanto sopra (lettura) + leggere l'audit log | modificare dati |

Lo script verifica da solo i permessi effettivi e interrompe il deploy se non corrispondono a questa matrice.

## Dataset simulato e privacy by design

Tre soggetti **fittizi** con sede in Sicilia:

| Azienda | Settore (Allegato I) | Categoria | Città |
|---|---|---|---|
| Zagara Neuro Therapeutics S.p.A. | Sanitario – fabbricanti di prodotti farmaceutici | Essenziale (grande impresa) | Catania, Paternò |
| Elymsol Energia S.p.A. | Energia – produttori di energia elettrica | Essenziale (grande impresa) | Palermo, Enna, Gela, Mazara del Vallo |
| TecPot Digital Services S.r.l. | Gestione dei servizi TIC B2B – servizi gestiti | Importante (media impresa) | Messina, Siracusa |

Il dataset non contiene dati personali reali:

- persone, indirizzi, aziende e contratti sono inventati;
- le partite IVA sono formalmente valide ma generate artificialmente;
- e-mail e domini usano il TLD riservato `.example` (RFC 2606), gli IP i blocchi di documentazione (RFC 5737, RFC 3849);
- non sono memorizzati codici fiscali di persone fisiche.

Eventuali omonimie con soggetti reali sono casuali.

## Licenza

Distribuito con licenza MIT (vedi `LICENSE`).
