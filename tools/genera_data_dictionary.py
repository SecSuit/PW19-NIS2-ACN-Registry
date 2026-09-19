#!/usr/bin/env python3
"""Genera docs/data_dictionary.md leggendo il catalogo di PostgreSQL (COMMENT ON,
tipi, vincoli, indici). Uso: python tools/genera_data_dictionary.py "dbname=nis2_acn user=postgres"
Richiede psql nel PATH. Il documento resta così sempre allineato allo schema."""
import subprocess, sys, datetime

CONN = sys.argv[1] if len(sys.argv) > 1 else "dbname=nis2_acn"

def q(sql):
    out = subprocess.run(["psql", CONN, "-XAt", "-F", "\x1f", "-R", "\x1e", "-c", sql],
                         capture_output=True, text=True, check=True).stdout
    return [r.split("\x1f") for r in out.strip("\x1e\n").split("\x1e") if r]

def md(s):
    return (s or "").replace("|", "\\|").replace("\n", " ")

GRUPPI = [
    ("Tabelle di dominio (lookup)", ['paese','settore','sottosettore','tipologia_soggetto','categoria_soggetto',
      'dimensione_impresa','livello_criticita','tipo_asset','classificazione_informazione','tipo_dipendenza_asset',
      'tipo_fornitura','criterio_rilevanza','ruolo']),
    ("Anagrafiche e responsabilità", ['organizzazione','sede','persona','assegnazione_ruolo']),
    ("Asset e servizi", ['asset','servizio','servizio_paese','servizio_asset','dipendenza_asset']),
    ("Terze parti", ['fornitore','contratto','dipendenza_fornitore']),
    ("Perimetro di rete", ['spazio_ip','dominio']),
    ("Audit", ['audit_log']),
]

out = []
out.append("# Data dictionary – schema `nis2`\n")
out.append(f"Generato automaticamente dal catalogo di PostgreSQL con `tools/genera_data_dictionary.py` "
           f"il {datetime.date.today():%d/%m/%Y}. Descrizioni = `COMMENT ON` definiti negli script SQL.\n")
out.append("Legenda: **PK** chiave primaria · **FK** chiave esterna · **UK** vincolo di unicità · "
           "**NN** NOT NULL · CHECK/EXCLUDE = vincoli di dominio.\n")
out.append("Le 9 tabelle `*_storico` (organizzazione, sede, persona, assegnazione_ruolo, asset, servizio, fornitore, "
           "contratto, dipendenza_fornitore) hanno le stesse colonne della tabella corrente più `valido_al`, "
           "`operazione`, `motivo`, `archiviato_da`; chiave primaria `(<tabella>_id, versione)`. Sono descritte in fondo.\n")

toc = []
for titolo, tabs in GRUPPI:
    out.append(f"\n## {titolo}\n")
    for t in tabs:
        desc = q(f"SELECT obj_description('nis2.{t}'::regclass,'pg_class')")[0][0]
        nrows = q(f"SELECT count(*) FROM nis2.{t}")[0][0]
        out.append(f"\n### `nis2.{t}`\n\n{md(desc)}\n\nRighe nel dataset di test: {nrows}.\n")
        cols = q(f"""
          SELECT a.attname, format_type(a.atttypid,a.atttypmod), a.attnotnull::text,
                 coalesce(pg_get_expr(d.adbin,d.adrelid),''),
                 coalesce(a.attidentity,''),
                 coalesce(col_description(a.attrelid,a.attnum),''),
                 coalesce((SELECT string_agg(CASE c.contype WHEN 'p' THEN 'PK' WHEN 'u' THEN 'UK' WHEN 'f' THEN 'FK→'||
                          (SELECT relname FROM pg_class WHERE oid=c.confrelid) END, ', ')
                    FROM pg_constraint c WHERE c.conrelid=a.attrelid AND a.attnum = ANY(c.conkey) AND c.contype IN ('p','u','f')),'')
            FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
           WHERE a.attrelid='nis2.{t}'::regclass AND a.attnum>0 AND NOT a.attisdropped ORDER BY a.attnum""")
        out.append("| Colonna | Tipo | Chiavi | NN | Default | Descrizione |\n|---|---|---|---|---|---|")
        for name, typ, nn, dfl, ident, cdesc, keys in cols:
            if ident == 'a': dfl = 'IDENTITY ALWAYS'
            out.append(f"| `{name}` | {typ} | {keys} | {'sì' if nn in ('t','true') else ''} | {md(dfl)} | {md(cdesc)} |")
        cons = q(f"""SELECT conname, pg_get_constraintdef(oid) FROM pg_constraint
                     WHERE conrelid='nis2.{t}'::regclass AND contype IN ('c','x','u','f') ORDER BY contype, conname""")
        if cons:
            out.append("\n**Vincoli**\n")
            for n, dfn in cons:
                out.append(f"- `{n}`: `{md(dfn)}`")
        idx = q(f"""SELECT indexname, indexdef FROM pg_indexes WHERE schemaname='nis2' AND tablename='{t}'
                    AND indexname NOT IN (SELECT conname FROM pg_constraint WHERE conrelid='nis2.{t}'::regclass)
                    ORDER BY 1""")
        if idx:
            out.append("\n**Indici secondari**\n")
            for n, dfn in idx:
                out.append(f"- `{n}`: `{md(dfn.split(' USING ',1)[-1])}`")
        trg = q(f"""SELECT tgname FROM pg_trigger WHERE tgrelid='nis2.{t}'::regclass AND NOT tgisinternal ORDER BY 1""")
        if trg:
            out.append("\n**Trigger**: " + ", ".join(f"`{r[0]}`" for r in trg))

out.append("\n## Tabelle di storico\n")
out.append("| Tabella | Colonne aggiuntive | Chiave primaria | Righe nel dataset |\n|---|---|---|---|")
for (t,) in q("SELECT relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE nspname='nis2' AND relkind='r' AND relname LIKE '%\\_storico' ORDER BY 1"):
    n = q(f"SELECT count(*) FROM nis2.{t}")[0][0]
    out.append(f"| `nis2.{t}` | valido_al, operazione (U/D), motivo, archiviato_da | ({t[:-8]}_id, versione) | {n} |")

out.append("\n## Viste, funzioni e procedure\n")
out.append("| Oggetto | Tipo | Descrizione |\n|---|---|---|")
for n, d in q("SELECT c.relname, obj_description(c.oid,'pg_class') FROM pg_class c JOIN pg_namespace s ON s.oid=c.relnamespace WHERE s.nspname='nis2' AND c.relkind='v' ORDER BY 1"):
    out.append(f"| `nis2.{n}` | vista | {md(d)} |")
for n, k, d in q("SELECT p.oid::regprocedure::text, CASE p.prokind WHEN 'p' THEN 'procedura' ELSE 'funzione' END, obj_description(p.oid,'pg_proc') FROM pg_proc p JOIN pg_namespace s ON s.oid=p.pronamespace WHERE s.nspname='nis2' ORDER BY 1"):
    out.append(f"| `{n}` | {k} | {md(d)} |")

open(sys.argv[2] if len(sys.argv) > 2 else "docs/data_dictionary.md", "w", encoding="utf-8").write("\n".join(out) + "\n")
print("data dictionary generato")
