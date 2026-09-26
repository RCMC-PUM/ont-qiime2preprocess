// Prepends the QIIME 2 header to the collected "<sample-id>\t<abs-path>" rows,
// producing a SingleEndFastqManifestPhred33V2-compatible file for the oriented
// FASTQs. This is a convenience for the downstream QIIME 2 import step; it does
// not run QIIME 2 itself.

process WRITE_QIIME_MANIFEST {

    tag "qiime2-manifest"

    container 'staphb/samtools:1.22.1'   // just needs a shell + coreutils
    conda "${projectDir}/env/ont_env.yaml"

    publishDir "${params.outdir}", mode: params.publish_mode

    input:
    path(rows)

    output:
    path("qiime2-manifest.tsv")

    script:
    """
    set -euo pipefail
    {
        printf 'sample-id\\tabsolute-filepath\\n'
        cat ${rows}
    } > qiime2-manifest.tsv
    """
}
