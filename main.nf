#!/usr/bin/env nextflow
/*
 * EPICARD ONT 16S rRNA preprocessing
 * BAM -> FASTQ -> QC -> length/quality filter -> QC -> strand orientation -> MultiQC
 *
 * Derived from 4-Qiime2_analysis.ipynb (the per-sample Python loop),
 * turned into a per-sample Nextflow workflow driven by the sample manifest.
 */

nextflow.enable.dsl = 2

include { SAMTOOLS_FASTQ                 } from './modules/local/samtools_fastq.nf'
include { NANOPLOT_RAW ; NANOPLOT_FILT   } from './modules/local/nanoplot.nf'
include { NANOFILT                       } from './modules/local/nanofilt.nf'
include { VSEARCH_ORIENT                 } from './modules/local/vsearch_orient.nf'
include { MULTIQC                        } from './modules/local/multiqc.nf'
include { WRITE_QIIME_MANIFEST           } from './modules/local/write_qiime_manifest.nf'

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

// Resolve a manifest path: absolute stays as-is, relative is anchored at params.input_dir
def resolvePath = { p ->
    def pp = (p as String).trim()
    def f  = file(pp)
    return f.isAbsolute() ? f : file("${params.input_dir}/${pp}")
}

// ---------------------------------------------------------------------------
// Workflow
// ---------------------------------------------------------------------------

workflow {

    log.info """
    ================================================================
     EPICARD ONT 16S preprocessing
    ----------------------------------------------------------------
     manifest      : ${params.manifest}
     input_dir     : ${params.input_dir}
     merge chunks  : ${params.merge_barcode_bams}
     reference db  : ${params.ref_db}
     outdir        : ${params.outdir}
     filter        : len ${params.min_len}-${params.max_len} bp, Q>=${params.qscore}
     max_cpus/mem  : ${params.max_cpus} / ${params.max_memory}
    ================================================================
    """.stripIndent()

    // Reference database is reused by every sample -> value channel
    ch_db = Channel.value( file(params.ref_db, checkIfExists: true) )

    // One entry per manifest row: [ meta, [bam(s)] ]
    ch_samples = Channel
        .fromPath(params.manifest, checkIfExists: true)
        .splitCsv(header: true)
        .map { row ->
            def meta = [
                id      : (row.id ?: '').trim(),
                barcode : (row.barcode    ?: '').trim(),
                run     : (row.run   ?: '').trim()
            ]
            if( !meta.id || !meta.barcode )
                error "Manifest row missing id/barcode: ${row}"

            def rawp = (row.bam_path ?: '').trim()
            if( !rawp )
                error "Manifest row '${meta.id}' has an empty bam_path"

            def bamref = resolvePath(rawp)
            def bams
            if( params.merge_barcode_bams ) {
                // Combine every chunk MinKNOW/dorado wrote for this barcode
                bams = files("${bamref.parent}/*.bam").sort()
                if( !bams )
                    error "No .bam files found in ${bamref.parent} (sample ${meta.id})"
            }
            else {
                if( !bamref.exists() )
                    error "BAM not found for sample ${meta.id}: ${bamref}"
                bams = [ bamref ]
            }
            tuple(meta, bams)
        }

    // BAM -> FASTQ
    SAMTOOLS_FASTQ( ch_samples )

    // QC on the unaligned BAM(s)
    NANOPLOT_RAW( ch_samples )

    // Length + quality filtering
    NANOFILT( SAMTOOLS_FASTQ.out.fastq )

    // QC on the filtered reads
    NANOPLOT_FILT( NANOFILT.out.fastq )

    // Strand orientation against SILVA
    VSEARCH_ORIENT( NANOFILT.out.fastq, ch_db )

    // Aggregate both NanoPlot passes into one report
    ch_nanostats = NANOPLOT_RAW.out.stats
                        .mix( NANOPLOT_FILT.out.stats )
                        .collect()
    MULTIQC( ch_nanostats )

    // Convenience: QIIME 2 SingleEndFastqManifestPhred33V2 for the oriented reads
    ch_rows = VSEARCH_ORIENT.out.oriented
        .map { meta, fq ->
            def abs = file("${params.outdir}/oriented/${meta.run}/${meta.barcode}/${fq.name}").toAbsolutePath()
            "${meta.id}\t${abs}"
        }
        .collectFile(name: 'qiime2-manifest.rows.tsv', newLine: true, sort: true)
    WRITE_QIIME_MANIFEST( ch_rows )
}

workflow.onComplete {
    log.info ( workflow.success
        ? "\nDone. Results in: ${params.outdir}\n"
        : "\nFailed after ${workflow.duration}. See .nextflow.log\n" )
}
