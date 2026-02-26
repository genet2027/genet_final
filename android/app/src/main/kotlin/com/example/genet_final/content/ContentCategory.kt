package com.example.genet_final.content

/**
 * A category within a section (e.g. "לימודים ועתיד" under Content Library).
 * Filtered by minAge and targetGender.
 * @param targetGender "all" | "male" | "female" – if not "all", only that gender from minAge sees it.
 */
data class ContentCategory(
    val id: String,
    val section: ContentSection,
    val titleHeb: String,
    val iconEmoji: String,
    val minAge: Int,
    val targetGender: String = "all", // "all" | "male" | "female"
    val topics: List<ContentTopic> = emptyList(),
    /** If true, this category is part of the mandatory 14+ set (מס הכנסה, ביטוח לאומי, צבא, שירות לאומי). */
    val isMandatory14Plus: Boolean = false
) {
    fun isVisibleFor(userAge: Int, userGender: String): Boolean {
        if (userAge < minAge) return false
        if (targetGender == "all") return true
        return targetGender == userGender
    }
}
