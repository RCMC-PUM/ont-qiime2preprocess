process MULTIQC {

    tag "nanoplot"

    container 'multiqc/multiqc:v1.35'
    conda 'bioconda::multiqc=1.35'

    // Some MultiQC images set an ENTRYPOINT to `multiqc`; empty it so Nextflow's
    // own command runs. Harmless no-op if the image has no entrypoint.
    containerOptions '--entrypoint ""'

    publishDir { "${params.outdir}/QC/multiqc" }, mode: params.publish_mode

    input:
    path('nanoplot_stats/*')

    output:
    path("multiqc_report.html"), emit: report
    path("multiqc_data")       , emit: data

    script:
    """
    set -euo pipefail
    export HOME="\$PWD"
    export MPLCONFIGDIR="\$PWD/.mplconfig"; mkdir -p "\$MPLCONFIGDIR"

    multiqc nanoplot_stats \\
        --module nanostat \\
        --filename multiqc_report.html
    """
}
