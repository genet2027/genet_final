package com.example.genet_final.content

/**
 * SUGGESTED Jetpack Compose UI layout for Genet content.
 *
 * To use: add Compose to the module (build.gradle.kts):
 *   buildFeatures { compose = true }
 *   composeOptions { kotlinCompilerExtensionVersion = "1.5.14" }
 *   dependencies { implementation(platform("androidx.compose:compose-bom:2024.06.00")) }
 *
 * This file is a REFERENCE only; the app's main UI is Flutter.
 * You can port this structure to Flutter or use it in a native Compose screen.
 */

/*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.text.style.TextAlign

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GenetContentScreen(
    userAge: Int,
    userGender: String,
    modifier: Modifier = Modifier
) {
    val content = remember(userAge, userGender) {
        ContentRepository.getAvailableContent(userAge, userGender)
    }
    val scrollState = rememberScrollState()

    Column(modifier = modifier.verticalScroll(scrollState)) {
        content[ContentSection.CONTENT_LIBRARY]?.let { categories ->
            SectionHeader(ContentSection.CONTENT_LIBRARY.titleHeb)
            categories.forEach { category ->
                ContentCategoryCard(category = category)
                Spacer(modifier = Modifier.height(12.dp))
            }
        }
        Spacer(modifier = Modifier.height(24.dp))
        content[ContentSection.BIG_BROTHER]?.let { categories ->
            SectionHeader(ContentSection.BIG_BROTHER.titleHeb)
            categories.forEach { category ->
                ContentCategoryCard(category = category)
                Spacer(modifier = Modifier.height(12.dp))
            }
        }
        Spacer(modifier = Modifier.height(32.dp))
    }
}

@Composable
private fun SectionHeader(title: String) {
    Text(
        text = title,
        style = MaterialTheme.typography.titleLarge,
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
    )
}

@Composable
private fun ContentCategoryCard(
    category: ContentCategory,
    modifier: Modifier = Modifier
) {
    Card(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
        shape = MaterialTheme.shapes.medium
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(
                text = "${category.iconEmoji} ${category.titleHeb}",
                style = MaterialTheme.typography.titleMedium,
                textAlign = TextAlign.End
            )
            Spacer(modifier = Modifier.height(12.dp))
            category.topics.forEach { topic ->
                TopicRow(topic = topic)
                Spacer(modifier = Modifier.height(8.dp))
            }
        }
    }
}

@Composable
private fun TopicRow(topic: ContentTopic) {
    Column {
        Text(
            text = topic.titleHeb,
            style = MaterialTheme.typography.bodyLarge,
            textAlign = TextAlign.End
        )
        if (topic.bulletPoints.isNotEmpty()) {
            topic.bulletPoints.forEach { bullet ->
                Text(
                    text = "• $bullet",
                    style = MaterialTheme.typography.bodySmall,
                    textAlign = TextAlign.End,
                    modifier = Modifier.padding(start = 16.dp)
                )
            }
        }
    }
}
*/
