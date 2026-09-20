# Guida al popolamento e alla manutenzione del registro NIS2/ACN

Questa guida è rivolta a chi alimenta e mantiene il registro (punto di contatto NIS, CISO, amministratore del database). Tutti gli esempi sono eseguibili nel Query Tool di pgAdmin 4 o in psql.

## 0. Pulizia e creazione del database (pgAdmin 4)

1. Collegarsi al database **`postgres`** (Query Tool aperto su `postgres`): non si può eliminare il database a cui si è collegati.
2. Eseguire **da solo**: `DROP DATABASE IF EXISTS nis2_acn WITH (FORCE);`
3. Eseguire **da solo**: `CREATE DATABASE nis2_acn ENCODING 'UTF8' TEMPLATE template0;`
4. Premere **F5** per aggiornare l'albero, poi aprire il **PSQL Tool** su `nis2_acn` ed eseguire `\i 'C:/PW19-NIS2-ACN-Registry/sql/00_run_all.sql'`.

I due comandi dei punti 2 e 3 vanno eseguiti separatamente, altrimenti si ottiene l'errore `cannot run inside a transaction block`.

## 1. Principi

1. **Una sola fonte di verità.** Asset, servizi, fornitori e responsabilità si aggiornano solo nel registro. Il profilo ACN si genera dal registro e non si compila più a mano.
2. **Mai testo libero per le categorie.** Tipi, criticità, criteri e ruoli sono codici delle tabelle di dominio. Per aggiungere un valore nuovo si inserisce prima una riga nella lookup, poi la si usa (§ 5).
3. **Ogni modifica ha un motivo.** Prima di modificare dati di conformità, dichiarare il motivo nella stessa transazione: finisce nello storico e nell'audit log.
4. **Non si cancella ciò che si può chiudere.** Un incarico terminato si chiude con `data_fine`, un contratto scaduto con la sua data di scadenza. La cancellazione fisica è riservata agli errori di inserimento, e anche in quel caso resta traccia nello storico.

## 2. Ordine di popolamento

Le chiavi esterne impongono quest'ordine:

| Passo | Tabella | Prerequisiti |
|---|---|---|
| 1 | `organizzazione` | lookup `tipologia_soggetto`, `categoria_soggetto`, `dimensione_impresa` |
| 2 | `sede` (almeno la sede LEGALE) | organizzazione |
| 3 | `persona` | – |
| 4 | `assegnazione_ruolo` | organizzazione, persona, `ruolo` |
| 5 | `asset` | organizzazione, persona (proprietario), sede facoltativa |
| 6 | `servizio`, `servizio_paese` | organizzazione, persona (responsabile), `macro_area`, `categoria_rilevanza` |
| 7 | `servizio_asset`, `dipendenza_asset` | servizi e asset della **stessa** organizzazione |
| 8 | `fornitore` | `paese`; se il fornitore è censito, la sua organizzazione |
| 9 | `contratto` | organizzazione, fornitore |
| 10 | `dipendenza_fornitore` | contratto e **un solo** tra servizio e asset |
| 11 | `spazio_ip`, `dominio` | organizzazione |

Il file `sql/07_dati_test.sql` mostra un popolamento completo. I riferimenti vi sono risolti per codice (es. `WHERE codice = 'ZNT-MES-01'`) e non per identificativo numerico: è la tecnica consigliata anche per i caricamenti reali.

## 3. Operazioni ricorrenti

### 3.1 Modificare un dato con motivo

```sql
BEGIN;
SELECT nis2.fn_imposta_motivo('BIA 2027: revisione RTO del MES');
UPDATE nis2.asset SET rto_minuti = 180 WHERE codice = 'ZNT-MES-01';
COMMIT;
```

Il trigger incrementa `versione` e archivia la versione precedente in `asset_storico`. Un UPDATE che non cambia alcun valore non genera né versioni né righe di audit.

### 3.2 Sostituire il punto di contatto (o un altro ruolo unico)

```sql
CALL nis2.sp_sostituisci_titolare_ruolo(
     1, 'PUNTO_CONTATTO', <persona_id>, DATE '2027-01-01',
     'Dimissioni del precedente punto di contatto', 'Delibera CdA 15/12/2026');
```

La procedura chiude l'incarico in corso al giorno precedente la decorrenza e apre il nuovo, nella stessa transazione. Un inserimento diretto senza chiusura viene rifiutato con errore `NIS02`.

### 3.3 Registrare un nuovo fornitore rilevante

1. Inserire il fornitore in `fornitore`. Per un fornitore italiano la partita IVA viene verificata automaticamente.
2. Inserire il contratto indicando `clausole_sicurezza`, `dpa_art28`, `diritto_audit` e `notifica_incidenti_ore`.
3. Collegare il contratto a ogni servizio o asset che dipende dal fornitore (`dipendenza_fornitore`), con criterio di rilevanza (`TIC` o `NON_FUNGIBILE`) e codice CPV.

### 3.4 Categorizzare le attività e i servizi (art. 30; Det. ACN 155238/2026)

Ogni riga di `servizio` (tutte le attività, interne ed esterne, non solo quelle nel perimetro NIS) indica la **macro-area** e la **categoria di rilevanza**. Il modello (Allegato 1 o 2) dipende dal settore del soggetto. Se la categoria scelta differisce da quella pre-assegnata alla macro-area, va compilata `valutazione_categoria`, altrimenti il trigger rifiuta la modifica con `NIS09`. L'elenco da riportare sulla piattaforma (1° maggio–30 giugno) è la vista `nis2.v_categorizzazione_attivita`.

### 3.5 Consultare la situazione a una data passata

```sql
SELECT nis2.fn_record_alla_data('contratto', 3, TIMESTAMPTZ '2026-06-30 12:00');
SELECT * FROM nis2.fn_asset_alla_data(2, TIMESTAMPTZ '2026-06-30 12:00');
```

### 3.6 Generare ed esportare il profilo ACN

- Vista di tutte le organizzazioni: `SELECT * FROM nis2.v_profilo_acn;`
- Una sola organizzazione: `SELECT * FROM nis2.fn_profilo_acn(<id>);`
- CSV dal **Query Tool**: eseguire la query e premere **Save results to file** (freccia verso il basso sopra la griglia, F8).
- CSV dal **PSQL Tool**: `\copy` lato client; lo script `export/esporta_profili_csv.sql` esporta tutti i profili in un colpo solo.
- Non usare `COPY ... TO 'percorso'` lato server: su Windows il servizio PostgreSQL non può scrivere nelle cartelle dell'utente.

## 4. Controlli periodici consigliati

| Frequenza | Controllo | Query |
|---|---|---|
| Mensile | Contratti di fornitori rilevanti in scadenza | Q8 di `08_query_profilo_acn.sql` |
| Trimestrale | Fornitori extra UE, contratti senza clausole di sicurezza o senza DPA | Q7 |
| Prima di ogni finestra di aggiornamento verso l'ACN | Esecuzione della suite di test e confronto dei conteggi del profilo | `tests/test_integrita_e_versioning.sql`, Q6 |
| Annuale | Revisione di criticità, RTO e RPO dopo la Business Impact Analysis | `v_asset_critici` |

## 5. Evoluzione dello schema

- **Nuovi valori di dominio:** `INSERT INTO nis2.ruolo (...) VALUES (...);`. Tutti gli script di dominio usano `ON CONFLICT DO NOTHING`.
- **Nuova colonna in una tabella storicizzata:** aggiungere la stessa colonna (stesso nome e tipo) **sia** alla tabella corrente **sia** alla tabella `_storico`, nella stessa transazione. Il trigger di storico copia i valori per nome di colonna (`jsonb_populate_record`), quindi l'ordine delle colonne non conta:

  ```sql
  BEGIN;
  ALTER TABLE nis2.asset          ADD COLUMN fornitore_manutenzione varchar(100);
  ALTER TABLE nis2.asset_storico  ADD COLUMN fornitore_manutenzione varchar(100);
  COMMIT;
  ```

  Se la colonna viene dimenticata nello storico, i valori storici di quella colonna non vengono conservati. Il test T38 della suite rileva la regressione sui campi esistenti.
- **Versionamento degli script:** ogni modifica passa da un commit Git con un messaggio descrittivo. Le release consegnate si marcano con un tag (`v1.0`, `v1.1`, …) e si registrano in `nis2_meta.versione_schema`; ogni esecuzione di `00_run_all.sql` aggiunge una riga a `nis2_meta.registro_deploy`. Gli script numerati rendono ripetibile il deploy da zero.

## 6. Sicurezza e privacy in esercizio

- **Ruoli applicativi:** sono creati da `sql/09_sicurezza_versione.sql` (minimo privilegio, verifica automatica dei permessi). Per abilitare una persona si crea un utente con login e gli si assegna il ruolo adatto:

  ```sql
  CREATE ROLE m_rossi LOGIN PASSWORD 'da-cambiare';
  GRANT nis2_redattore TO m_rossi;   -- oppure nis2_lettura / nis2_revisore
  ```

  Le tabelle di dominio si modificano solo con l'utente amministratore.
- I trigger rendono storico e audit immutabili a livello di riga. Il `TRUNCATE` va inoltre revocato a tutti i ruoli applicativi, perché non attiva trigger di riga.
- **Minimizzazione:** per le persone si conservano solo dati di contatto professionali, senza codice fiscale. Il registro non contiene dati sanitari né dati sugli incidenti.
- **Backup:** usare `pg_dump -Fc -n nis2 nis2_acn > nis2_AAAAMMGG.dump` e cifrare le copie, perché il registro descrive gli asset critici ed è a sua volta un'informazione riservata.

## 7. Risoluzione dei problemi

| Errore | Significato | Soluzione |
|---|---|---|
| `23514` check violation | Valore fuori dominio (P.IVA, e-mail, CAP, date, RTO/RPO mancanti per asset critico) | Correggere il valore. Il nome del vincolo nel messaggio indica la regola violata (vedi data dictionary). |
| `23503` / `23001` | Riferimento inesistente, oppure cancellazione impedita da `ON DELETE RESTRICT` | Inserire prima il padre, oppure rimuovere o chiudere prima i figli. |
| `NIS02` | Ruolo unico già assegnato nel periodo | Usare `sp_sostituisci_titolare_ruolo`. |
| `NIS03` | Punto di contatto e sostituto coincidono | Nominare persone diverse. |
| `NIS04` | Dipendenza circolare tra asset | Rivedere il verso della dipendenza. |
| `NIS05` | Elementi di organizzazioni diverse collegati tra loro | Per i legami con terzi usare `contratto` e `dipendenza_fornitore`. |
| `NIS06` | Tentativo di modificare storico o audit | Operazione non ammessa per progetto. |
| `NIS09` | Categoria di rilevanza diversa da quella pre-assegnata alla macro-area, senza motivazione | Compilare `valutazione_categoria` (Det. ACN 155238/2026, art. 3, c. 3). |
