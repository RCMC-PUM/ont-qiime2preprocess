# ONT 16S samples preprocessing pipeline (Nextflow)

Per-sample preprocessing for the ONT 16S rRNA samples in Nextflow DSL2.

Per sample the pipeline runs:

```
uBAM ─▶ samtools fastq ─▶ FASTQ ─▶ NanoFilt ─▶ filtered FASTQ ─▶ vsearch --orient ─▶ oriented FASTQ
        │                                    │
        └▶ NanoPlot (raw, --ubam)            └▶ NanoPlot (filtered, --fastq)
                    └──────────────┬──────────────┘
                                   ▼
                              MultiQC report
```

It also writes a QIIME 2-ready manifest of the oriented reads for the next step.

## Requirements

- Nextflow ≥ 23.04
- One software backend: **Docker** (default), **Conda/Mamba**, or **Singularity/Apptainer** (HPC)

## Quick start

```bash
# Docker (recommended on a workstation)
nextflow run $PIPELINE_PATH -profile docker -params-file $PARAMS_PATH/params.yaml

# Conda
nextflow run $PIPELINE_PATH -profile conda -params-file $PARAMS_PATH/params.yaml

# HPC (e.g. Cyfronet Helios): Singularity, optionally with SLURM
nextflow run $PIPELINE_PATH -profile singularity,slurm -params-file $PARAMS_PATH/params.yaml
```

Launch from your analysis directory: by default the manifest is read from
`<launch dir>/metadata/sample-manifest.csv` and the reference from
`<launch dir>/misc/ref/SILVA_144_SSURef_NR99_tax_silva_trunc.fasta`.
To use other locations, set `manifest` / `ref_db` in `params.yaml` as absolute paths.

## Input manifest

CSV with a header row (this is example from `sample-manifest-epicard.csv`):

```
patient_id,barcode,run_name,bam_path
01-039,barcode01,16S_BG_16012026,../data/basecalled/BATCH_1/bam_pass/barcode01/PBI53311_pass_barcode01_..._0.bam
```

- `sample_id` — used as the sample id and in every output filename
- `barcode`, `run_name` — used to build the output directory tree
- `bam_path` — path to the sample's BAM. Relative paths are resolved against
  `params.input_dir` (default `.`), so launching from your analysis directory
  makes the `../data/...` paths resolve exactly as they did in the notebook.

## Outputs (`results/`)

```
results/
├── fastq/<run>/<barcode>/<pid>_<bc>.fastq
├── filtered/<run>/<barcode>/<pid>_<bc>.filtered.fastq
├── oriented/<run>/<barcode>/<pid>_<bc>.filtered.oriented.fastq   (+ .tabout, .unmatched.fastq, .vsearch.log)
├── QC/
│   ├── initial/<pid>_<bc>_raw/        (NanoPlot on the raw uBAM)
│   ├── posthoc/<pid>_<bc>_filt/       (NanoPlot on the filtered reads)
│   └── multiqc/multiqc_report.html
├── qiime2-manifest.tsv                (SingleEndFastqManifestPhred33V2 for the oriented reads)
└── pipeline_info/                     (timeline / report / trace / dag)
```

## Key parameters (`params.yaml`)

| param | default | meaning |
|---|---|---|
| `manifest` | `<launch dir>/metadata/sample-manifest.csv` | input CSV |
| `input_dir` | `.` | anchor for relative `bam_path` values |
| `merge_barcode_bams` | `false` | merge all `*.bam` chunks per barcode (see note) |
| `ref_db` | `<launch dir>/misc/ref/SILVA_144_SSURef_NR99_tax_silva_trunc.fasta` | orientation reference |
| `min_len` / `max_len` / `qscore` | 800 / 2200 / 15 | NanoFilt thresholds |
| `threads` | 12 | cpus for MultiQC and the QIIME 2 manifest step |
| `max_cpus` | 32 | cpus shared by all running tasks of the pipeline (local executor only); also caps any single task |
| `max_memory` / `max_time` | 32.GB / 24.h | ceilings applied to every process |

## Container images

| step | image |
|---|---|
| samtools fastq | `staphb/samtools:1.22.1` |
| NanoPlot (both) | `staphb/nanoplot:1.46.2` |
| NanoFilt | `cautree/nanofilt:latest` |
| vsearch orient | `nanozoo/vsearch:2.30.4--d925d0f` |
| MultiQC | `multiqc/multiqc:v1.35` |

## Notes / caveats

- **vsearch `--orient` is single-threaded** (it warns and ignores extra
  threads), so that process is pinned to `cpus = 1`.

- **SILVA reference must be the unaligned NR99 FASTA**, not the
  `*_full_align_trunc` alignment export — the aligned file contains `.`/`-` gap
  characters that make vsearch abort with `Illegal character '.'`.

- **Docker** runs as your UID/GID (`-u $(id -u):$(id -g)`) so outputs aren't
  root-owned; `HOME`/`MPLCONFIGDIR` are redirected into the work dir so
  NanoPlot/MultiQC's matplotlib cache doesn't fail under a non-root user. The
  MultiQC process empties any image `ENTRYPOINT` as insurance.

- **HPC inputs outside the launch dir.** With Singularity, if `../data` lives
  outside the directory you launch from, you may need to bind it, e.g.
  `singularity.runOptions = '-B /scratch/epicard'` in the `singularity` profile.

## Next step (QIIME 2)

`results/qiime2-manifest.tsv` imports the oriented reads directly:

```bash
qiime tools import \
  --type 'SampleData[SequencesWithQuality]' \
  --input-format SingleEndFastqManifestPhred33V2 \
  --input-path results/qiime2-manifest.tsv \
  --output-path oriented-reads.qza
```
