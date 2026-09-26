process SAMTOOLS_FASTQ {

    tag "${meta.id}"

    container 'staphb/samtools:1.22.1'
    conda 'bioconda::samtools=1.22.1'

    publishDir "${params.outdir}/fastq/${meta.run}/${meta.barcode}", mode: params.publish_mode

    input:
    tuple val(meta), path(bams)

    output:
    tuple val(meta), path("${meta.id}_${meta.barcode}.fastq"), emit: fastq

    script:
    """
    set -euo pipefail

    nbam=\$(ls -1 *.bam 2>/dev/null | wc -l)
    if [ "\$nbam" -gt 1 ]; then
        # multiple chunks for this barcode -> concatenate at BAM level, then stream to FASTQ
        samtools cat -@ ${task.cpus} *.bam \\
            | samtools fastq -@ ${task.cpus} - > ${meta.id}_${meta.barcode}.fastq
    else
        samtools fastq -@ ${task.cpus} *.bam > ${meta.id}_${meta.barcode}.fastq
    fi
    """
}
