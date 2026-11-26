package com.scatl.folio

import com.scatl.folio.config.FolioProperties
import org.springframework.boot.autoconfigure.SpringBootApplication
import org.springframework.boot.context.properties.EnableConfigurationProperties
import org.springframework.boot.runApplication
import org.springframework.scheduling.annotation.EnableScheduling

@EnableScheduling
@EnableConfigurationProperties(FolioProperties::class)
@SpringBootApplication
class FolioApplication {
    companion object {
        @JvmStatic
        fun main(args: Array<String>) {
            runApplication<FolioApplication>(*args)
        }
    }
}
