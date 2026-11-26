package com.scatl.folio.settings

import org.springframework.context.ApplicationEvent

class AppSettingsChangedEvent(
    source: Any,
    val previous: RuntimeSettings?,
    val current: RuntimeSettings,
) : ApplicationEvent(source)
