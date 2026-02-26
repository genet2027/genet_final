package com.example.genet_final.content

/**
 * Optional: a single article under a topic (for future detail screens).
 */
data class Article(
    val id: String,
    val topicId: String,
    val titleHeb: String,
    val bodyHeb: String = "",
    val minAge: Int = 0,
    val targetGender: String = "all"
)
