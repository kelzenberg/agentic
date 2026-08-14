<!-- AI-drafted, 2026-06-09 -->

# Property + enum matching tiers

Deterministic six-tier sequence the skill applies wherever it needs to map a **logical name** (e.g. `Related Person`) to a **live property name** (e.g. `Persons`), and wherever it needs to map an **inferred enum value** (e.g. `High`) to a **live option name** (e.g. `Urgent`).

The sequence is applied identically in both cases. First hit wins; advancement only on miss. Same input + same live schema → same decision, every time.

This file is read once per session (or per matching call), primarily by the skill at workflow step 5.2. Adapter files also apply this tier sequence for type-filtered live-property lookups (e.g. finding the live `url`-typed property for `search_by_source_url`) against the schema the skill cached from `fetch_schema()` — see [Source URL property matching](#source-url-property-matching) below. Decision logic for enum-value misses (batching, prompting, memoization) stays skill-side; adapters never decide how an enum-value miss is resolved.

## The tier order

| Tier | Name | Rule | Deterministic? |
|---|---|---|---|
| 1 | **Exact** | NFC-normalized string equality. No transformation. | yes |
| 2 | **Case + whitespace fold** | Lowercase both sides, collapse internal whitespace runs to a single space, trim leading/trailing whitespace, compare for equality. | yes |
| 3 | **Morphological variants** | English suffix rules applied in both directions: drop trailing `s`, drop trailing `es`, swap trailing `ies` ↔ `y`. Then re-compare via tier 2 (case + whitespace fold). Skip if either side contains non-Latin characters. | yes |
| 4 | **Known translation table** | Look up the candidate in the translation table below. If both sides resolve to the same logical-field row, that's a hit. | yes |
| 5 | **LLM-fuzzy with confidence ≥ 0.8** | The LLM scores every remaining candidate on a 0–1 semantic-closeness scale. Accept the top candidate **only if** (a) its score is ≥ 0.8 **and** (b) no runner-up scores within 0.1 of it (forces an unambiguous winner). | bounded |
| 6 | **Ask the user** | Enum-value misses fall through to the batched enum-miss prompt in `SKILL.md` step 5.2 pass 2; property-name misses are skipped silently (the property does not exist on the board). Multiple tier-6 enum-miss fall-throughs in one capture are batched into a single `AskUserQuestion` call. | human |

### Tier 5 confidence specifics

The skill prompts the LLM with: the source name, the list of remaining candidate live names, and a request for `{ candidate: score }` pairs in JSON. The skill then applies the two rules above. If either rule fails, the workflow advances to tier 6.

The 0.8 / 0.1 thresholds are chosen to be conservative — better to ask the user occasionally than to memoize a wrong decision for the session. Adjust only with strong evidence that captures are stalling on user prompts.

### Why tiers 1–4 are listed as deterministic

They are pure string operations against either the input or a static lookup table. Two runs of the skill on the same input produce identical output regardless of which Claude release executes them, what the conversation history looks like, or what time of day it is.

### Why tier 5 is "bounded" rather than "yes"

Different Claude releases may score the same semantic similarity slightly differently. The threshold + margin rule keeps the variation contained: a candidate that scores 0.85 today and 0.82 tomorrow still passes. A candidate that scores 0.78 today and 0.82 tomorrow flips between tier 5 and tier 6 — acceptable because tier 6 is a user prompt, which is recoverable.

---

## Translation table

Static vocabulary covering the skill's logical fields and the inferred enum values across the top six European languages by user base (English baseline + German, French, Spanish, Italian, Portuguese, Dutch). Hand-extend by editing this file; no config change required.

The skill checks both directions: a logical field looking for a live property uses this table to expand its search; a live property looking for a logical field uses the same table in reverse.

### Logical fields

| Logical field | en | de | fr | es | it | pt | nl |
|---|---|---|---|---|---|---|---|
| Name | Name, Title | Name, Titel | Nom, Titre | Nombre, Título | Nome, Titolo | Nome, Título | Naam, Titel |
| Status | Status, State | Status, Zustand | Statut, État | Estado | Stato | Estado, Situação | Status, Toestand |
| Priority | Priority, Importance | Priorität, Wichtigkeit | Priorité, Importance | Prioridad, Importancia | Priorità, Importanza | Prioridade, Importância | Prioriteit, Belang |
| Tags | Tags, Labels, Themes | Etiketten, Stichwörter, Themen | Étiquettes, Mots-clés, Thèmes | Etiquetas, Temas | Etichette, Tag, Temi | Etiquetas, Marcadores, Temas | Labels, Etiketten, Thema's |
| Effort | Effort, Size, Complexity | Aufwand, Größe, Komplexität | Effort, Taille, Complexité | Esfuerzo, Tamaño, Complejidad | Sforzo, Dimensione, Complessità | Esforço, Tamanho, Complexidade | Inspanning, Grootte, Complexiteit |
| Due date | Due date, Deadline, Due | Fälligkeit, Frist, Fällig | Échéance, Date limite | Vencimiento, Fecha límite | Scadenza, Termine | Prazo, Data limite | Vervaldatum, Deadline |
| Source | Source, Origin | Quelle, Ursprung | Source, Origine | Fuente, Origen | Fonte, Origine | Fonte, Origem | Bron, Oorsprong |
| Source URL | Source URL, Link, URL | Quell-URL, Link, URL | URL source, Lien, URL | URL de origen, Enlace | URL sorgente, Collegamento | URL de origem, Ligação | Bron-URL, Link |
| Related Person | Related Person, Persons, People, Owner, Assignee | Verwandte Person, Personen, Verantwortlich, Zuständig | Personne liée, Personnes, Responsable | Persona relacionada, Personas, Responsable | Persona correlata, Persone, Responsabile | Pessoa relacionada, Pessoas, Responsável | Gerelateerde persoon, Personen, Verantwoordelijk |

### Inferred enum values

| Logical value | en | de | fr | es | it | pt | nl |
|---|---|---|---|---|---|---|---|
| High | High, Urgent, Critical | Hoch, Dringend, Kritisch | Haute, Urgent, Critique | Alta, Urgente, Crítica | Alta, Urgente, Critica | Alta, Urgente, Crítica | Hoog, Dringend, Kritiek |
| Medium | Medium, Normal, Standard | Mittel, Normal, Standard | Moyenne, Normal, Standard | Media, Normal, Estándar | Media, Normale, Standard | Média, Normal, Padrão | Gemiddeld, Normaal, Standaard |
| Low | Low, Minor, Backlog | Niedrig, Gering, Backlog | Basse, Faible, Différé | Baja, Menor, Diferida | Bassa, Minore, Differita | Baixa, Menor, Diferida | Laag, Klein, Uitgesteld |
| Quick | Quick, Fast, Short | Schnell, Kurz | Rapide, Court | Rápido, Corto | Veloce, Breve | Rápido, Curto | Snel, Kort |
| Deep | Deep, Long, Large | Tief, Lang, Groß | Profond, Long, Grand | Profundo, Largo, Grande | Profondo, Lungo, Grande | Profundo, Longo, Grande | Diep, Lang, Groot |
| Not started | Not started, To do, Open, Backlog, Inbox | Nicht begonnen, Offen, Zu erledigen, Inbox | À faire, Non commencé, Ouvert | Por hacer, No iniciado, Abierto | Da fare, Non iniziato, Aperto | A fazer, Não iniciado, Aberto | Te doen, Niet gestart, Open |
| In progress | In progress, Doing, Active, WIP | In Arbeit, Aktiv, Läuft | En cours, Actif | En curso, En progreso, Activo | In corso, In lavorazione, Attivo | Em andamento, Em curso, Ativo | Bezig, Lopend, Actief |
| Blocked | Blocked, Waiting, On hold, Stuck | Blockiert, Wartend, Pausiert | Bloqué, En attente, En pause | Bloqueado, En espera, En pausa | Bloccato, In attesa, In pausa | Bloqueado, Em espera, Em pausa | Geblokkeerd, Wachtend, Gepauzeerd |
| Done | Done, Complete, Completed, Closed, Finished | Erledigt, Fertig, Abgeschlossen, Geschlossen | Terminé, Fait, Achevé, Fermé | Terminado, Hecho, Completado, Cerrado | Fatto, Completato, Chiuso | Concluído, Feito, Completo, Fechado | Klaar, Voltooid, Gesloten |

### Notes on extending the table

- One row per logical field or logical enum value. Don't split a row across language columns.
- Comma-separate synonyms within a single language cell. The skill treats each comma-separated entry as a separate alias.
- Case-insensitive match at tier 4. The entries here use Title Case for legibility, but `priorität` would match `Priorität`.
- For boards that use idiosyncratic labels (e.g. `MyTeamTagThing`), prefer adding the alias to this file (where it benefits all users on that backend) rather than configuring a per-user override (which would resurrect the persisted-translation-layer pattern this skill deliberately avoids).

---

## Source URL property matching

The Notion adapter's `search_by_source_url` needs to find a `url`-typed property whose live name corresponds to `Source URL`. It applies the same tier sequence with one restriction: only `url`-typed properties are candidates. The tier match is computed against the property's live name, but the candidate pool is filtered by type first. If no `url`-typed property exists on the board, the function returns `null` without running the tier sequence at all.

Same shape for other type-filtered lookups (title-typed property for `Name`, status-typed for `Status`, etc.): filter by type, then apply tiers within the filtered pool.

---

## Anti-patterns

- **Don't add per-user entries to the table.** This file ships with the skill. User-specific aliases resurrect the persisted-translation-layer pattern.
- **Don't expand the tier sequence beyond six steps.** Adding tiers makes matching harder to reason about. If something fails at tier 6, the answer is a clearer prompt, not more tiers.
- **Don't lower the tier-5 thresholds without evidence.** A 0.7 threshold writes wrong values more often; the user gets pages tagged in ways they didn't intend.
- **Don't memoize tier-5 decisions to disk.** In-session memo only (see `SKILL.md` step 5.3). Persisting tier-5 picks would freeze the LLM's interpretation at a point in time and reintroduce the drift problem this skill is built to avoid.
- **Don't run enum-miss decision logic inside adapter operations.** Adapters may apply the tier sequence for type-filtered live-property lookups (see [Source URL property matching](#source-url-property-matching)), but batching, prompting, and memoizing enum-value misses happens skill-side. Centralizing enum-miss handling in one place keeps it consistent across backends.
