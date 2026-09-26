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
    // The nanostat module runs twice, splitting the report into "Before filtering"
    // (*_raw_NanoStats.txt) and "After filtering" (*_filt_NanoStats.txt) sections.
    // Sample names are cut down to the sample id:
    //   <id>_<barcode>_raw_NanoStats.txt -> <id>   (barcodes contain no "_", e.g. barcode01)
    """
    set -euo pipefail
    export HOME="\$PWD"
    export MPLCONFIGDIR="\$PWD/.mplconfig"; mkdir -p "\$MPLCONFIGDIR"

    cat > mqc_config.yml <<'EOF'
    module_order:
      - nanostat:
          name: "Before filtering"
          anchor: "nanostat_before"
          target: ""
          info: "NanoStat summary of the raw reads (unaligned BAM), before NanoFilt."
          path_filters:
            - "*_raw_NanoStats.txt"
      - nanostat:
          name: "After filtering"
          anchor: "nanostat_after"
          target: ""
          info: "NanoStat summary of the reads kept by NanoFilt (length ${params.min_len}-${params.max_len} bp, Q >= ${params.qscore})."
          path_filters:
            - "*_filt_NanoStats.txt"
    extra_fn_clean_exts:
      - type: regex
        pattern: '_[^_]+_(raw|filt)(_.*)?\$'
    EOF

    # Default names: multiqc_report.html + multiqc_data/ (matching the outputs above).
    # Note: --filename X.html would rename the data dir to X_data.
    multiqc nanoplot_stats \\
        --module nanostat \\
        --config mqc_config.yml
    """
}
