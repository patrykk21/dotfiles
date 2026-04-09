# notion-entry

Add research papers or YouTube videos to Notion Knowledge Base

## Usage

`/notion-entry <url> [database_id]`

## Default Database

- **Data Source ID**: `30e6d768-ec94-80f2-8490-000b9e565603`
- **Database ID**: `30e6d768-ec94-80c4-950f-fdbcece01f53`

Supported URLs:
- Research papers (PMC, ScienceDirect, arXiv, etc.)
- YouTube videos

## What it does

**For Research Papers:**
1. Fetches paper from provided URL using WebFetch
2. Extracts metadata (title, authors, journal, DOI, abstract, findings)
3. Creates database entry with Type=Research via Notion MCP
4. Adds comprehensive content (summary, findings, implications)

**For YouTube Videos:**
1. Fetches video information and metadata (title, channel, date, duration)
2. Downloads and extracts full transcript using yt-dlp
3. Analyzes transcript to generate comprehensive summary
4. Creates database entry with Type=Resource via Notion MCP
5. Adds video embed, transcript-based summary, key insights, and takeaways

## Implementation

**Use the first-party Claude AI Notion MCP connector** — NO local tokens or curl needed.

### Step 1: Fetch content from the URL
- For papers: Use `WebFetch` to extract title, authors, abstract, findings
- For YouTube: Use `yt-dlp` via Bash to download transcript, then analyze

### Step 2: Create the Notion page
Use `mcp__claude_ai_Notion__notion-create-pages` with:

```json
{
  "parent": {
    "type": "data_source_id",
    "data_source_id": "30e6d768-ec94-80f2-8490-000b9e565603"
  },
  "pages": [{
    "properties": {
      "Name": "Title of the entry",
      "Type": "Research or Resource",
      "Status": "To Explore",
      "Source": "https://original-url",
      "Category": "[\"Science\", \"Technology\"]",
      "Tags": "[\"Practical\", \"Modern\"]"
    },
    "content": "Notion-flavored Markdown content here (see Entry Formats below)"
  }]
}
```

### Property Schema
| Property | Type | Values |
|----------|------|--------|
| Name | title | Entry title |
| Type | select | Tool, Insight, Method, Resource, Quote, Research, Concept |
| Status | select | Applied, Understood, Learning, To Explore |
| Source | url | Original URL |
| Category | multi_select | History, Art, Mathematics, Cosmology, Literature, Productivity, Psychology, Technology, Science, Philosophy |
| Tags | multi_select | Must-Know, Modern, Historical, Theoretical, Practical, Fundamental |

## Entry Formats

### Research Papers
Content should include (as Notion Markdown):
- **Metadata** section: author, journal, DOI, PMCID
- **Summary** with subsections
- **Main Findings** (bulleted list)
- **Clinical/Theoretical Implications**
- **Critical Questions**
- **Methodology Notes**
- Properties: Type=Research, appropriate Category, Status=To Explore, Source URL, relevant Tags

### YouTube Videos
Content should include (as Notion Markdown):
- **Video metadata**: channel, published date, duration
- **Video embed**: embed the YouTube URL
- **Comprehensive Summary** (from transcript analysis)
- **Key Insights** and main points
- **Practical Takeaways** and applications
- **Personal Notes** section (empty, for user to fill)
- **Related Concepts** section
- Properties: Type=Resource, appropriate Category, Status=To Explore, Source URL, relevant Tags

**Transcript Extraction:**
```bash
# Uses yt-dlp to download and clean transcript
yt-dlp --write-auto-sub --sub-lang en --skip-download --sub-format vtt -o "transcript" "$URL"

# Clean VTT format to plain text
awk '
BEGIN { prev = "" }
/^WEBVTT/ { next }
/^Kind:/ { next }
/^Language:/ { next }
/^$/ { next }
/^[0-9][0-9]:/ { next }
/align:start/ { next }
{
    gsub(/<[^>]*>/, "")
    gsub(/^[ \t]+/, "")
    gsub(/[ \t]+$/, "")
    if (length($0) == 0) next
    if ($0 == prev) next
    printf "%s ", $0
    prev = $0
}
' transcript.en.vtt
```
