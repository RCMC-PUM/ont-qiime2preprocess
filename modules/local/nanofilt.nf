process NANOFILT {

    tag "${meta.id}"

    container 'cautree/nanofilt:latest'
    conda "${projectDir}/env/ont_env.yaml"

    publishDir "${params.outdir}/filtered/${meta.run}/${meta.barcode}", mode: params.publish_mode

    input:
    tuple val(meta), path(fastq)

    output:
    tuple val(meta), path("${meta.id}_${meta.barcode}.filtered.fastq"), emit: fastq

    script:
    // NanoFilt reads from stdin and writes to stdout (single-threaded).
    """
    set -euo pipefail

    NanoFilt \\
        --length ${params.min_len} \\
        --maxlength ${params.max_len} \\
        -q ${params.qscore} \\
        < ${fastq} \\
        > ${meta.id}_${meta.barcode}.filtered.fastq
    """
}
