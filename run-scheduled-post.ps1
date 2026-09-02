$ErrorActionPreference = "Stop"

try {

    # ============================================================
    # KONFIGURATION (aus Umgebungsvariablen / GitHub Secrets)
    # ============================================================

    $instagramUserId = $env:INSTAGRAM_USER_ID
    $instagramToken = $env:INSTAGRAM_TOKEN

    $cloudName = $env:CLOUDINARY_CLOUD_NAME
    $cloudinaryApiKey = $env:CLOUDINARY_API_KEY
    $cloudinaryApiSecret = $env:CLOUDINARY_API_SECRET

    $geminiApiKey = $env:GEMINI_API_KEY
    $geminiModel = "gemini-2.5-flash-image"

    $openAiKey = $env:OPENAI_API_KEY

    foreach ($name in @(
        "INSTAGRAM_USER_ID", "INSTAGRAM_TOKEN",
        "CLOUDINARY_CLOUD_NAME", "CLOUDINARY_API_KEY", "CLOUDINARY_API_SECRET",
        "GEMINI_API_KEY", "OPENAI_API_KEY"
    )) {
        if ([string]::IsNullOrEmpty([Environment]::GetEnvironmentVariable($name))) {
            throw "Umgebungsvariable fehlt: $name"
        }
    }


    # ============================================================
    # STIL-GUIDE (fuer visuell stimmige Postreihe)
    # ============================================================

    $styleGuide = "Flaches Vektor-Illustrationsdesign im Cartoon-Stil, dicke abgerundete Outlines, " +
        "warme Pastellfarbpalette aus Koralle (#FF6B6B), Tuerkis (#4ECDC4), Cremeweiss (#FFF5E1) und " +
        "Dunkelblau (#1A1A2E), freundliche minimalistische Formen, konsistente Bildsprache fuer eine " +
        "zusammenhaengende Social-Media-Postreihe zum Thema Webdesign, quadratisches Format, kein Text " +
        "und keine Schrift im Bild."


    # ============================================================
    # THEMENLISTE (rotiert automatisch, ohne gespeicherten Zustand)
    # ============================================================

    $topics = @(
        "Die erste Webseite der Welt (CERN, 1991)",
        "Warum Weissraum (White Space) im Design wichtig ist",
        "Die Drei-Klick-Regel bei der Navigation",
        "Farbpsychologie im Webdesign",
        "Mobile-First-Design und warum es zaehlt",
        "Ladezeiten und ihr Einfluss auf die Absprungrate",
        "Barrierefreiheit (Accessibility) im Webdesign",
        "Warum Schriftwahl ueber Vertrauen entscheidet",
        "Das F-Pattern beim Lesen von Webseiten",
        "Responsive Design und Breakpoints",
        "Microinteractions und User Engagement",
        "Dark Mode: Trend oder echtes Nutzerbeduerfnis",
        "Gibt es 'above the fold' heute noch wirklich",
        "Grid-Systeme als Basis fuer Layouts",
        "Warum Call-to-Action-Buttons starke Kontraste brauchen",
        "Skeleton Screens statt klassischer Ladebalken",
        "Runde vs. eckige Formen und ihre Wirkung im Design",
        "Wie Webfonts die Ladezeit beeinflussen",
        "Was ein Design System ist und warum es sich lohnt",
        "Negativer Raum als bewusstes Gestaltungselement"
    )

    $slotSeconds = 3 * 60 * 60
    $slotIndex = [int]([Math]::Floor(([DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) / $slotSeconds))
    $thema = $topics[$slotIndex % $topics.Count]


    # ============================================================
    # START
    # ============================================================

    $startTime = Get-Date

    Write-Host ""
    Write-Host "==============================================="
    Write-Host " AUTOMATISCHER INSTAGRAM UPLOADER (SCHEDULED)"
    Write-Host "==============================================="
    Write-Host ""
    Write-Host "Bildthema: $thema"


    # ============================================================
    # 1. BILD MIT NANO BANANA (GEMINI) GENERIEREN
    # ============================================================

    Write-Host ""
    Write-Host "1. Erstelle Bild mit Nano Banana..."
    Write-Host ""

    $imagePrompt = "$styleGuide Thema des Bildes: $thema."

    $geminiHeaders = @{
        "Content-Type" = "application/json; charset=utf-8"
    }

    $geminiBodyObject = @{
        contents = @(
            @{
                parts = @(
                    @{ text = $imagePrompt }
                )
            }
        )
        generationConfig = @{
            imageConfig = @{ aspectRatio = "1:1" }
        }
    }

    $geminiBody = $geminiBodyObject | ConvertTo-Json -Depth 10
    $geminiBodyBytes = [System.Text.Encoding]::UTF8.GetBytes($geminiBody)

    $geminiUrl = "https://generativelanguage.googleapis.com/v1beta/models/${geminiModel}:generateContent?key=$geminiApiKey"

    $geminiResponse = Invoke-RestMethod `
        -Uri $geminiUrl `
        -Method POST `
        -Headers $geminiHeaders `
        -Body $geminiBodyBytes

    $imagePart = $geminiResponse.candidates[0].content.parts |
        Where-Object { $_.inlineData } |
        Select-Object -First 1

    if ($null -eq $imagePart) {
        throw "Nano Banana hat kein Bild zurueckgegeben."
    }

    $imageBase64 = $imagePart.inlineData.data
    $imageMimeType = $imagePart.inlineData.mimeType

    Write-Host "Bild generiert ($imageMimeType)."


    # ============================================================
    # 2. BILD ZU CLOUDINARY HOCHLADEN
    # ============================================================

    Write-Host ""
    Write-Host "2. Lade Bild zu Cloudinary hoch..."
    Write-Host ""

    $timestamp = [int64]([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
    $paramsToSign = "timestamp=$timestamp"

    $sha1 = [System.Security.Cryptography.SHA1]::Create()
    $signatureBytes = $sha1.ComputeHash(
        [System.Text.Encoding]::UTF8.GetBytes("$paramsToSign$cloudinaryApiSecret")
    )
    $signature = ($signatureBytes | ForEach-Object { $_.ToString("x2") }) -join ""

    $dataUri = "data:$imageMimeType;base64,$imageBase64"

    $uploadBody = @{
        file      = $dataUri
        api_key   = $cloudinaryApiKey
        timestamp = $timestamp
        signature = $signature
    }

    $uploadResponse = Invoke-RestMethod `
        -Uri "https://api.cloudinary.com/v1_1/$cloudName/image/upload" `
        -Method POST `
        -Body $uploadBody

    $mediaUrl = $uploadResponse.secure_url

    if ([string]::IsNullOrEmpty($mediaUrl)) {
        throw "Cloudinary hat keine gueltige URL zurueckgegeben."
    }

    Write-Host "Hochgeladen:"
    Write-Host $mediaUrl


    # ============================================================
    # 3. GPT-5.4 CAPTION ERSTELLEN
    # ============================================================

    Write-Host ""
    Write-Host "3. Erstelle Caption mit GPT-5.4..."
    Write-Host ""

    $openAiHeaders = @{
        "Authorization" = "Bearer $openAiKey"
        "Content-Type" = "application/json; charset=utf-8"
    }

    $captionPrompt = @"
Erstelle eine interessante Instagram-Caption auf Deutsch.

Thema:
$thema

Anforderungen:

- 2 bis 4 kurze Absaetze
- passend zum Bildinhalt (Webdesign-Thema)
- informativ oder unterhaltsam
- keine erfundenen Fakten
- passend fuer Instagram
- maximal 700 Zeichen
- am Ende 5 bis 8 passende Hashtags
- keine Anfuehrungszeichen
- keine Einleitung wie "Hier ist deine Caption"
"@

    $openAiBodyObject = @{
        model = "gpt-5.4"
        input = $captionPrompt
    }

    $openAiBody = $openAiBodyObject | ConvertTo-Json -Depth 10
    $openAiBodyBytes = [System.Text.Encoding]::UTF8.GetBytes($openAiBody)

    $openAiResponse = Invoke-RestMethod `
        -Uri "https://api.openai.com/v1/responses" `
        -Method POST `
        -Headers $openAiHeaders `
        -Body $openAiBodyBytes

    $caption = $openAiResponse.output[0].content[0].text

    if ([string]::IsNullOrEmpty($caption)) {
        throw "GPT-5.4 hat keine Caption zurueckgegeben."
    }

    Write-Host "Caption:"
    Write-Host "--------------------------------"
    Write-Host $caption
    Write-Host "--------------------------------"


    # ============================================================
    # 4. INSTAGRAM CONTAINER ERSTELLEN
    # ============================================================

    $instagramHeaders = @{
        "Authorization" = "Bearer $instagramToken"
        "Content-Type" = "application/json; charset=utf-8"
    }

    Write-Host ""
    Write-Host "4. Erstelle Instagram-Container..."
    Write-Host ""

    $instagramBodyObject = @{
        image_url = $mediaUrl
        caption   = $caption
    }

    $instagramBody = $instagramBodyObject | ConvertTo-Json -Depth 10
    $instagramBodyBytes = [System.Text.Encoding]::UTF8.GetBytes($instagramBody)

    $container = Invoke-RestMethod `
        -Uri "https://graph.instagram.com/v23.0/$instagramUserId/media" `
        -Method POST `
        -Headers $instagramHeaders `
        -Body $instagramBodyBytes

    $creationId = $container.id

    if ([string]::IsNullOrEmpty($creationId)) {
        throw "Instagram hat keine Creation ID zurueckgegeben."
    }

    Write-Host "Container erstellt:"
    Write-Host $creationId


    # ============================================================
    # 5. BIS ZU 300 SEKUNDEN WARTEN UND VEROEFFENTLICHEN
    # ============================================================

    Write-Host ""
    Write-Host "5. Warte auf Instagram-Verarbeitung..."
    Write-Host ""

    $published = $null

    for ($i = 300; $i -gt 0; $i -= 5) {

        Start-Sleep -Seconds 5

        try {
            $publishBody = @{ creation_id = $creationId } | ConvertTo-Json
            $publishBodyBytes = [System.Text.Encoding]::UTF8.GetBytes($publishBody)

            $published = Invoke-RestMethod `
                -Uri "https://graph.instagram.com/v23.0/$instagramUserId/media_publish" `
                -Method POST `
                -Headers $instagramHeaders `
                -Body $publishBodyBytes

            Write-Host "Instagram ist bereit!"
            break
        }
        catch {
            Write-Host "Noch nicht bereit, verbleibende Zeit: $i Sekunden..."
        }
    }


    # ============================================================
    # 6. ERGEBNIS
    # ============================================================

    if ($null -eq $published) {
        Write-Host ""
        Write-Host "==============================================="
        Write-Host "NICHT VEROEFFENTLICHT (Timeout nach 300s)"
        Write-Host "==============================================="
        exit 1
    }
    else {
        $endTime = Get-Date
        $duration = $endTime - $startTime

        Write-Host ""
        Write-Host "==============================================="
        Write-Host "ERFOLGREICH VEROEFFENTLICHT"
        Write-Host "==============================================="
        Write-Host "Instagram Media ID: $($published.id)"
        Write-Host "Bildthema: $thema"
        Write-Host "Cloudinary URL: $mediaUrl"
        Write-Host "Gesamtdauer: $($duration.Minutes) Minuten und $($duration.Seconds) Sekunden"
    }

}
catch {

    Write-Host ""
    Write-Host "==============================================="
    Write-Host "FEHLER"
    Write-Host "==============================================="
    Write-Host $_.Exception.Message

    if ($_.ErrorDetails.Message) {
        Write-Host ""
        Write-Host "API-Antwort:"
        Write-Host $_.ErrorDetails.Message
    }

    exit 1
}
