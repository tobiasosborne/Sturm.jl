# Literature Survey Reporting Standard

Each agent must report findings in this exact format:

## Per-paper entry:

```
### [SHORT_TAG] Author et al. (YEAR) — Title
- **arXiv/DOI**: arXiv:XXXX.XXXXX or doi:XX.XXXX/XXXXX
- **PDF status**: downloaded / not_found / paywalled
- **Category**: (one of) ZX_CALCULUS | T_COUNT | CLIFFORD_OPT | CNOT_OPT | ROUTING | SYNTHESIS | ML_SEARCH | PHASE_POLY | PEEPHOLE | RESOURCE_EST | FAULT_TOLERANT | CATEGORY_THEORY | VARIATIONAL | MCGS | OTHER
- **Key idea** (1-2 sentences): What is the core technique?
- **Relevance to Sturm.jl** (1 sentence): How would this apply to our DAG IR?
- **Cites/cited-by**: Key related papers (by SHORT_TAG)
```

## Summary section (end of each agent report):

```
## TOPIC SUMMARY
- Papers found: N
- Papers downloaded: M
- Top 3 most relevant to Sturm.jl: [TAG1], [TAG2], [TAG3]
- Key insight for implementation: (1-2 sentences)
```
