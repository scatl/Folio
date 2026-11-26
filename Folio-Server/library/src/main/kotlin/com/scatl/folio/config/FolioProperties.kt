package com.scatl.folio.config

import org.springframework.boot.context.properties.ConfigurationProperties

@ConfigurationProperties(prefix = "folio")
class FolioProperties {
    var library = Library()

    class Library {
        /** ffprobe 可执行文件。环境变量：FOLIO_FFPROBE */
        var ffprobe: String = "ffprobe"

        /** ffmpeg 可执行文件。环境变量：FOLIO_FFMPEG */
        var ffmpeg: String = "ffmpeg"
    }
}
