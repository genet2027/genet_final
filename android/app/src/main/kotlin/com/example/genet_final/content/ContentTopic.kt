package com.example.genet_final.content

/**
 * A topic under a content category. Contains title and optional bullet points (sub-items).
 */
data class ContentTopic(
    val id: String,
    val titleHeb: String,
    val bulletPoints: List<String> = emptyList()
)
