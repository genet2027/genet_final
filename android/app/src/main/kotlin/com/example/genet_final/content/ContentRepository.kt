package com.example.genet_final.content

/**
 * Pre-loads and filters Genet content by age and gender.
 * Age groups: Beginners (13–14), Advanced (15–16), Mature (17+).
 * Special: 14+ must include מס הכנסה, ביטוח לאומי, צבא, שירות לאומי.
 * Certain topics targeted for males 13+ (targetGender = "male").
 */
object ContentRepository {

    private val allCategories: List<ContentCategory> by lazy { buildAllCategories() }

    /**
     * Returns only content allowed for this user based on age tiers and special rules.
     * @param userAge age of the user (e.g. from child profile)
     * @param userGender "male" | "female"
     * @return categories grouped by section, each category with its topics (already filtered)
     */
    fun getAvailableContent(
        userAge: Int,
        userGender: String
    ): Map<ContentSection, List<ContentCategory>> {
        val filtered = allCategories.filter { cat ->
            when {
                cat.isMandatory14Plus -> userAge >= 14
                else -> cat.isVisibleFor(userAge, userGender)
            }
        }
        return filtered.groupBy { it.section }
    }

    /**
     * Flat list of all available categories for this user (for simpler UI iteration).
     */
    fun getAvailableCategoriesFlat(userAge: Int, userGender: String): List<ContentCategory> {
        return getAvailableContent(userAge, userGender).values.flatten()
    }

    private fun buildAllCategories(): List<ContentCategory> = listOf(
        // ========== Section 1: Content Library (ספריית תכנים) ==========
        ContentCategory(
            id = "lib_studies",
            section = ContentSection.CONTENT_LIBRARY,
            titleHeb = "לימודים ועתיד",
            iconEmoji = "📚 🎯",
            minAge = 13,
            topics = listOf(
                ContentTopic(
                    id = "lib_studies_success",
                    titleHeb = "הצלחה בלימודים",
                    bulletPoints = listOf(
                        "איך ללמוד נכון למבחן",
                        "סיכומים חכמים",
                        "ניהול זמן",
                        "התמודדות עם לחץ"
                    )
                ),
                ContentTopic(
                    id = "lib_studies_thinking",
                    titleHeb = "חשיבה ופתרון בעיות",
                    bulletPoints = listOf(
                        "חשיבה ביקורתית",
                        "קבלת החלטות",
                        "פתרון קונפליקטים",
                        "יצירתיות"
                    )
                ),
                ContentTopic(
                    id = "lib_studies_goals",
                    titleHeb = "הצבת מטרות",
                    bulletPoints = listOf(
                        "חלומות ויעדים",
                        "תכנון עתידי",
                        "משמעת עצמית",
                        "התמדה"
                    )
                )
            )
        ),
        ContentCategory(
            id = "lib_money",
            section = ContentSection.CONTENT_LIBRARY,
            titleHeb = "כסף וחיים",
            iconEmoji = "💼 💰",
            minAge = 15,
            topics = listOf(
                ContentTopic(
                    id = "lib_money_finance",
                    titleHeb = "חינוך פיננסי",
                    bulletPoints = listOf(
                        "מה זה משכורת",
                        "איך חוסכים",
                        "כרטיס אשראי",
                        "ניהול תקציב"
                    )
                ),
                ContentTopic(
                    id = "lib_money_work",
                    titleHeb = "עולם העבודה",
                    bulletPoints = listOf(
                        "מקצועות מבוקשים",
                        "יזמות צעירה"
                    )
                )
            )
        ),
        ContentCategory(
            id = "lib_digital",
            section = ContentSection.CONTENT_LIBRARY,
            titleHeb = "דיגיטל ומדיה",
            iconEmoji = "🌐",
            minAge = 13,
            topics = listOf(
                ContentTopic(
                    id = "lib_digital_safe",
                    titleHeb = "גלישה חכמה",
                    bulletPoints = listOf(
                        "סכנות ברשת",
                        "פרטיות",
                        "פייק ניוז",
                        "התמכרות למסכים"
                    )
                ),
                ContentTopic(
                    id = "lib_digital_tech",
                    titleHeb = "טכנולוגיה בסיסית",
                    bulletPoints = listOf(
                        "איך אפליקציות עובדות",
                        "AI למתחילים",
                        "תכנות בסיסי",
                        "שימוש חכם בנייד"
                    )
                )
            )
        ),
        // Mandatory 14+ (Content Library)
        ContentCategory(
            id = "lib_mandatory_14",
            section = ContentSection.CONTENT_LIBRARY,
            titleHeb = "מגיל 14",
            iconEmoji = "📋",
            minAge = 14,
            isMandatory14Plus = true,
            topics = listOf(
                ContentTopic(id = "lib_tax", titleHeb = "מס הכנסה", bulletPoints = emptyList()),
                ContentTopic(id = "lib_bituach", titleHeb = "ביטוח לאומי", bulletPoints = emptyList()),
                ContentTopic(id = "lib_army", titleHeb = "צבא", bulletPoints = emptyList()),
                ContentTopic(id = "lib_sherut", titleHeb = "שירות לאומי", bulletPoints = emptyList())
            )
        ),

        // ========== Section 2: Big Brother (אח גדול) ==========
        ContentCategory(
            id = "bb_body",
            section = ContentSection.BIG_BROTHER,
            titleHeb = "גוף ואורח חיים",
            iconEmoji = "🏃 ⚽",
            minAge = 13,
            topics = listOf(
                ContentTopic(
                    id = "bb_body_sport",
                    titleHeb = "ספורט וכושר",
                    bulletPoints = listOf(
                        "בניית שגרה",
                        "מוטיבציה",
                        "תזונה לספורטאים",
                        "מניעת פציעות"
                    )
                ),
                ContentTopic(
                    id = "bb_body_lifestyle",
                    titleHeb = "אורח חיים בריא",
                    bulletPoints = listOf(
                        "שינה טובה",
                        "תזונה נכונה",
                        "היגיינה",
                        "איזון מסכים"
                    )
                )
            )
        ),
        ContentCategory(
            id = "bb_relationships",
            section = ContentSection.BIG_BROTHER,
            titleHeb = "חברה וזוגיות",
            iconEmoji = "🤝",
            minAge = 13,
            topics = listOf(
                ContentTopic(
                    id = "bb_rel_teen",
                    titleHeb = "זוגיות בגיל ההתבגרות",
                    bulletPoints = listOf(
                        "רגשות ראשונים",
                        "כבוד הדדי",
                        "לחץ חברתי",
                        "מערכות יחסים בריאות"
                    )
                ),
                ContentTopic(
                    id = "bb_rel_communication",
                    titleHeb = "תקשורת בין־אישית",
                    bulletPoints = listOf(
                        "חברויות בריאות",
                        "גבולות",
                        "כבוד הדדי",
                        "פתרון ריבים"
                    )
                )
            )
        ),
        ContentCategory(
            id = "bb_mind",
            section = ContentSection.BIG_BROTHER,
            titleHeb = "נפש וחוסן אישי",
            iconEmoji = "🧠 ❤️",
            minAge = 13,
            topics = listOf(
                ContentTopic(
                    id = "bb_mind_confidence",
                    titleHeb = "ביטחון עצמי",
                    bulletPoints = listOf(
                        "אהבה עצמית",
                        "התמודדות עם ביקורת",
                        "דימוי גוף",
                        "עמידה מול קהל"
                    )
                ),
                ContentTopic(
                    id = "bb_mind_health",
                    titleHeb = "בריאות נפשית",
                    bulletPoints = listOf(
                        "התמודדות עם לחץ",
                        "חרדה בגיל ההתבגרות",
                        "ויסות רגשי",
                        "מתי לבקש עזרה"
                    )
                )
            )
        )
    )
}
