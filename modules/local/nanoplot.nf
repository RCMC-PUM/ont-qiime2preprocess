// NanoPlot QC. Two entry points share the same image/env:
//   NANOPLOT_RAW  -> runs on the unaligned BAM(s)   (pre-filter)
//   NANOPLOT_FILT -> runs on the filtered FASTQ      (post-filter)
// A unique --prefix per run keeps NanoStats filenames distinct so MultiQC
// names every sample (and both passes) uniquely.

process NANOPLOT_RAW {

    tag { meta.id }

    container 'staphb/nanoplot:1.46.2'
    conda "${projectDir}/env/ont_env.yaml"

    publishDir { "${params.outdir}/QC/initial" }, mode: params.publish_mode

    input:
    tuple val(meta), path(bams)

    output:
    path("${meta.id}_${meta.barcode}_raw")                                              , emit: report
    path("${meta.id}_${meta.barcode}_raw/${meta.id}_${meta.barcode}_raw_NanoStats.txt"), emit: stats

    script:
    """
    set -euo pipefail
    export HOME="\$PWD"
    export MPLCONFIGDIR="\$PWD/.mplconfig"; mkdir -p "\$MPLCONFIGDIR"

    NanoPlot \\
        --ubam ${bams} \\
        --threads ${task.cpus} \\
        --prefix ${meta.id}_${meta.barcode}_raw_ \\
        --outdir ${meta.id}_${meta.barcode}_raw
    """
}

process NANOPLOT_FILT {

    tag { meta.id }

    container 'staphb/nanoplot:1.46.2'
    conda "${projectDir}/env/ont_env.yaml"

    publishDir { "${params.outdir}/QC/posthoc" }, mode: params.publish_mode

    input:
    tuple val(meta), path(fastq)

    output:
    path("${meta.id}_${meta.barcode}_filt")                                               , emit: report
    path("${meta.id}_${meta.barcode}_filt/${meta.id}_${meta.barcode}_filt_NanoStats.txt"), emit: stats

    script:
    """
    set -euo pipefail
    export HOME="\$PWD"
    export MPLCONFIGDIR="\$PWD/.mplconfig"; mkdir -p "\$MPLCONFIGDIR"

    NanoPlot \\
        --fastq ${fastq} \\
        --threads ${task.cpus} \\
        --prefix ${meta.id}_${meta.barcode}_filt_ \\
        --outdir ${meta.id}_${meta.barcode}_filt
    """
}
