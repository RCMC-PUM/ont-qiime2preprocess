process VSEARCH_ORIENT {

    tag { meta.id }

    container 'nanozoo/vsearch:2.30.4--d925d0f'
    conda 'bioconda::vsearch=2.30.4'

    publishDir { "${params.outdir}/oriented/${meta.run}/${meta.barcode}" }, mode: params.publish_mode

    input:
    tuple val(meta), path(fastq)
    path db

    output:
    tuple val(meta), path("${meta.id}_${meta.barcode}.filtered.oriented.fastq"), emit: oriented
    path("${meta.id}_${meta.barcode}.tabout")                                  , emit: tabbed
    path("${meta.id}_${meta.barcode}.unmatched.fastq")                         , emit: notmatched
    path("${meta.id}_${meta.barcode}.vsearch.log")                             , emit: log

    script:
    // NOTE: `vsearch --orient` is single-threaded (it warns and ignores extra
    // threads); this process is given cpus=1 in nextflow.config accordingly.
    // The query file is the argument to --orient, NOT a trailing positional.
    """
    set -euo pipefail

    vsearch \\
        --orient ${fastq} \\
        --db ${db} \\
        --fastqout ${meta.id}_${meta.barcode}.filtered.oriented.fastq \\
        --tabbedout ${meta.id}_${meta.barcode}.tabout \\
        --notmatched ${meta.id}_${meta.barcode}.unmatched.fastq \\
        --threads ${task.cpus} \\
        --log ${meta.id}_${meta.barcode}.vsearch.log
    """
}
