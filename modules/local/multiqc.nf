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
    // bin/nanostats_to_mqc.py turns the NanoStats files into MultiQC custom content,
    // named by sample id: General Statistics with before/after columns, plus
    // "Before filtering" / "After filtering" sections (stats table + quality plot).
    // (The nanostat module can't be run twice here: both runs share column keys
    //  and plot ids, so the "after" values overwrite the "before" ones.)
    """
    set -euo pipefail
    export HOME="\$PWD"
    export MPLCONFIGDIR="\$PWD/.mplconfig"; mkdir -p "\$MPLCONFIGDIR"

    nanostats_to_mqc.py nanoplot_stats mqc_custom \\
        --filter-info "length ${params.min_len}-${params.max_len} bp, Q >= ${params.qscore}"

    cat > mqc_config.yml <<'EOF'
    report_section_order:
      before_filtering:
        order: 20
      after_filtering:
        order: 10
    EOF

    # Default names: multiqc_report.html + multiqc_data/ (matching the outputs above).
    # Note: --filename X.html would rename the data dir to X_data.
    multiqc mqc_custom \\
        --module custom_content \\
        --config mqc_config.yml
    """
}
