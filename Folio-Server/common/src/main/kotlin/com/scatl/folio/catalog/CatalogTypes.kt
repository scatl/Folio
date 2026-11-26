package com.scatl.folio.catalog

enum class WorkKind {
    movie,
    series,
}

enum class OwnerType {
    work,
    season,
    episode,
    person,
}

enum class ExternalProvider {
    tmdb,
    tvdb,
    imdb,
    rottentomatoes,
    rt_audience,
    metacritic,
    wikidata,
    facebook,
    instagram,
    twitter,
    tvrage,
    freebase,
}

enum class ArtworkKind {
    poster,
    backdrop,
    still,
    logo,
    collection_poster,
    collection_backdrop,
}
