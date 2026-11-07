# ass-media legge per riflessione questi campi privati di MatroskaExtractor
# (AssMatroskaExtractor): senza regola R8 li rinomina e i video MKV vanno in crash.
-keepclassmembers class androidx.media3.extractor.mkv.MatroskaExtractor {
    androidx.media3.extractor.ExtractorOutput extractorOutput;
    androidx.media3.common.util.ParsableByteArray subtitleSample;
}
