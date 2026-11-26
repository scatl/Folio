package com.scatl.folio.config

import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration
import org.springframework.scheduling.concurrent.ThreadPoolTaskExecutor

@Configuration
class LibraryScanConfig {
    @Bean(name = ["libraryScanExecutor"])
    fun libraryScanExecutor(): ThreadPoolTaskExecutor =
        ThreadPoolTaskExecutor().apply {
            corePoolSize = 1
            maxPoolSize = 1
            queueCapacity = 256
            setThreadNamePrefix("library-scan-")
            initialize()
        }

    @Bean(name = ["manualMatchExecutor"])
    fun manualMatchExecutor(): ThreadPoolTaskExecutor =
        ThreadPoolTaskExecutor().apply {
            corePoolSize = 2
            maxPoolSize = 2
            queueCapacity = 32
            setThreadNamePrefix("manual-match-")
            initialize()
        }
}
