#!/usr/bin/env python3
"""Render one slideshow variant to PNGs.

Layout is HTML/CSS rendered by headless Chrome; the photo compositing that CSS
cannot do (the 4-point screen warp) happens in plates.py first. Nothing here is
generative — same inputs give byte-identical output, which is the whole point.

    python3 render.py ja-001     # Japanese post 001
    python3 render.py --list     # every buildable post

Naming, one rule: a variant key is <lang>-<what>, and it renders to
`out/<lang>/<format>/<post>/NN_slide.png`.

  ja-001 ... ja-006        Japanese posts, numbered in posting order
  en-cards, en-flat, ...   English style experiments, not scheduled posts

`format` is the reusable template in words (`must-have-apps`), so a folder says what
it is without a lookup. `FORMAT-TESTS.md` still carries the registry code (H5-CB) for
that format; the words and the code refer to the same thing.

Japan is the live campaign — every TikTok account posts in Japanese — so the ja-NNN
series is the thing being scheduled and the English variants are reference only.
"""

import html
import math
import os
import pathlib
import shutil
import subprocess
import sys

from PIL import Image, ImageDraw

import plates

ROOT = pathlib.Path(__file__).resolve().parent
ICONS = ROOT / "icons"
FONTS = ROOT / "fonts"
PLATES = ROOT / "plates"
SHOTS = ROOT / "shots"
OUT = ROOT / "out"
WEB_MARK = ROOT.parents[2] / "web" / "public" / "mac-mark.png"
# One directory per process. Account renders are safe to run in parallel, and one
# process can no longer delete another process's HTML before Chrome has loaded it.
WORK = ROOT / ".work" / str(os.getpid())

CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
W, H = plates.CANVAS
# The fan must fit *inside* the laptop lid, because only the lid can occlude it.
# Overlap fraction and the size clamp are the two knobs; the size itself is derived
# from each photo's measured lid width, so a laptop that sits smaller in frame gets
# proportionally smaller icons instead of icons hanging over the wall beside it.
ICON_OVERLAP = 0.16
ICON_MIN, ICON_MAX = 118, 210
FAN_INSET = 40          # keep the outermost icons clear of the lid's rounded corners


def fan_icon_px(lid_width, n):
    if n < 1:
        return ICON_MAX
    span = max(1.0, lid_width - 2 * FAN_INSET)
    raw = span / (n - ICON_OVERLAP * (n - 1))
    return int(max(ICON_MIN, min(ICON_MAX, raw)))

# ---------------------------------------------------------------- the variant

APPS = [
    {"name": "Ice", "icon": "ice.png", "visual": "ice.png",
     "copy": "Hides the menu bar clutter you never look at and keeps what you "
             "actually use one click away. Your top bar finally looks as clean as "
             "the rest of your Mac."},
    {"name": "DockDoor", "icon": "dockdoor.png", "visual": "dockdoor.png",
     "copy": "Hover any app in your Dock and see live previews of every open "
             "window. Switching stops being guesswork and starts feeling instant."},
    {"name": "KeigoButton", "icon": "keigobutton.png", "visual": "keigobutton.png",
     "copy": "Rewrite text without leaving the app you're in. Select anything in "
             "Slack, Gmail or Notion, press one of your own buttons, and it's "
             "polished, shortened or translated in place."},
    {"name": "Dropover", "icon": "dropover.png", "visual": "dropover.png",
     "copy": "Drop files onto a floating shelf and carry them anywhere. No more "
             "lining up two windows side by side just to move one thing across."},
]

APPS_JA = [
    {"name": "Ice", "icon": "ice.png", "visual": "ice.png",
     "copy": "メニューバーのごちゃつきを隠して、必要なアイコンだけを表示。"
             "Macの画面がすっきり整う。"},
    {"name": "DockDoor", "icon": "dockdoor.png", "visual": "dockdoor.png",
     "copy": "Dockのアプリにカーソルを合わせるだけで、開いているウインドウを一覧表示。"
             "アプリの切り替えが一気に速くなる。"},
    {"name": "敬語ボタン", "slug": "keigobutton", "icon": "keigobutton.png",
     "visual": "keigobutton_ja.png",
     "copy": "Slackやメールで文章を選び、ボタンを押すだけ。敬語・要約・英訳など、"
             "よく使うAIへの指示をどのアプリからでも実行できる。"},
    {"name": "Dropover", "icon": "dropover.png", "visual": "dropover.png",
     "copy": "ファイルを一時置きできる浮遊シェルフ。ウインドウを並べなくても、"
             "ドラッグ＆ドロップで移動がラクになる。"},
]

APPS_JA_02 = [
    {"name": "Shottr", "icon": "shottr.png", "visual": "shottr.png",
     "copy": "軽くて高機能なスクショアプリ。スクロール撮影、OCR、注釈、"
             "色の取得まで、1本で完結する。"},
    {"name": "Rectangle", "icon": "rectangle.png", "visual": "rectangle.png",
     "copy": "ショートカットや画面端へのドラッグで、ウインドウを左右・最大化に整列。"
             "毎日の画面整理が一気に速くなる。"},
    {"name": "敬語ボタン", "slug": "keigobutton", "icon": "keigobutton.png",
     "visual": "keigobutton_ja.png",
     "copy": "Slackやメールで文章を選び、ボタンを押すだけ。敬語・要約・英訳など、"
             "よく使うAIへの指示をどのアプリからでも実行できる。"},
    {"name": "Maccy", "icon": "maccy.png", "visual": "maccy.png",
     "copy": "コピー履歴をキーボードで呼び出せる、軽量クリップボード管理。"
             "前にコピーした文章やURLをすぐ再利用できる。"},
]

APPS_JA_03 = [
    {"name": "Stats", "icon": "stats.png", "visual": "stats.png",
     "copy": "CPU・メモリ・ディスク・通信量などをメニューバーで確認。"
             "Macの負荷がひと目で分かる。"},
    {"name": "AltTab", "icon": "alttab.png", "visual": "alttab.png",
     "copy": "開いているウインドウをプレビュー付きで切り替え。"
             "アプリ単位ではなく、使いたい窓をそのまま選べる。"},
    {"name": "敬語ボタン", "slug": "keigobutton", "icon": "keigobutton.png",
     "visual": "keigobutton_ja.png",
     "copy": "Slackやメールで文章を選び、ボタンを押すだけ。敬語・要約・英訳など、"
             "よく使うAIへの指示をどのアプリからでも実行できる。"},
    {"name": "MonitorControl", "icon": "monitorcontrol.png",
     "visual": "monitorcontrol.png",
     "copy": "外部モニターの明るさや音量を、Macのキーボードから調整。"
             "純正ディスプレイのように操作できる。"},
]

# Posts 004-006 introduce nine new utilities, each used exactly once. The assets and
# claims come from their official Mac App Store records (LocalSend's visual comes from
# its official desktop site); SOURCES.json pins every URL and hash.
APPS_JA_04 = [
    {"name": "MeetingBar", "icon": "meetingbar.png", "visual": "meetingbar.png",
     "copy": "次の予定をメニューバーに表示。Google MeetやZoomへの参加も、"
             "ワンクリックで済む。"},
    {"name": "Hand Mirror", "slug": "handmirror", "icon": "handmirror.png",
     "visual": "handmirror.png",
     "copy": "ビデオ会議の前に、メニューバーからカメラ映りをすぐ確認。"
             "髪型や背景をチェックできる。"},
    APPS_JA[2],
    {"name": "LocalSend", "icon": "localsend.png", "visual": "localsend.png",
     "copy": "同じWi-Fi上のMac・iPhone・Windowsへファイルを直接送信。"
             "アカウントもクラウドも不要。"},
]

APPS_JA_05 = [
    {"name": "Velja", "icon": "velja.png", "visual": "velja.png",
     "copy": "リンクを開くブラウザをその場で選択。仕事用と個人用をルールで"
             "自動的に振り分けられる。"},
    {"name": "Keka", "icon": "keka.png", "visual": "keka.png",
     "copy": "ZIP・7Z・RARなどを圧縮・解凍。パスワード付きファイルも"
             "シンプルに扱える。"},
    APPS_JA[2],
    {"name": "CotEditor", "icon": "coteditor.png", "visual": "coteditor.png",
     "copy": "Mac向けの軽快なテキストエディタ。シンタックス表示や検索・置換で、"
             "コードも文章も編集しやすい。"},
]

APPS_JA_06 = [
    {"name": "Amphetamine", "icon": "amphetamine.png", "visual": "amphetamine.png",
     "copy": "指定した時間だけMacのスリープを防止。ダウンロードや長い処理を"
             "途中で止めたくない時に便利。"},
    {"name": "Pure Paste", "slug": "purepaste", "icon": "purepaste.png",
     "visual": "purepaste.png",
     "copy": "コピーした文章の書式を自動で外して貼り付け。フォントや色が"
             "勝手についてくる問題をなくせる。"},
    APPS_JA[2],
    {"name": "GrandPerspective", "icon": "grandperspective.png",
     "visual": "grandperspective.png",
     "copy": "ストレージの中身を色付きの四角で可視化。容量を占領している"
             "大きなファイルをすぐ見つけられる。"},
]

# ---------------------------------------------------------------- English track
# GTM.md 2.2: the English market has no keigo concept, so ours is pitched as a
# system-wide AI writing shortcut and the word never appears. Same four-app lists and
# same plates as ja-001..006 so language stays the only campaign-level variable, but
# the copy is written for the English account rather than translated from the Japanese.
KEIGO_EN = {
    "name": "KeigoButton", "icon": "keigobutton.png", "visual": "keigobutton.png",
    "copy": "Stop tabbing out to ChatGPT to fix one sentence. Highlight text "
            "anywhere \u2014 Slack, Gmail, Notion \u2014 hit one of your own buttons and it "
            "rewrites in place. Your prompts, but as buttons.",
}

APPS_EN_01 = [
    {"name": "Ice", "icon": "ice.png", "visual": "ice.png",
     "copy": "Your menu bar has fourteen icons and you use three. Ice hides the "
             "rest behind one arrow, so the top of your screen stops looking like "
             "a browser with 40 tabs open."},
    {"name": "DockDoor", "icon": "dockdoor.png", "visual": "dockdoor.png",
     "copy": "Hover any Dock icon and every open window shows up as a live "
             "preview. No more clicking through six Chrome windows hunting for the "
             "one with your actual work in it."},
    KEIGO_EN,
    {"name": "Dropover", "icon": "dropover.png", "visual": "dropover.png",
     "copy": "Grab some files, shake your cursor, and they land on a floating "
             "shelf you can carry anywhere. Lining up two windows just to drag one "
             "thing across is officially over."},
]

APPS_EN_02 = [
    {"name": "Shottr", "icon": "shottr.png", "visual": "shottr.png",
     "copy": "Screenshots with range: scrolling capture, OCR so you can copy text "
             "straight out of an image, annotations, colour picker. Weighs almost "
             "nothing."},
    {"name": "Rectangle", "icon": "rectangle.png", "visual": "rectangle.png",
     "copy": "Drag a window to any edge and it snaps. Halves, quarters, full "
             "screen, all from the keyboard. Resizing windows by hand was never a "
             "personality trait."},
    KEIGO_EN,
    {"name": "Maccy", "icon": "maccy.png", "visual": "maccy.png",
     "copy": "Everything you have ever copied, one shortcut away. Copied over the "
             "link you actually needed? Still in there. Genuinely a memory "
             "upgrade."},
]

APPS_EN_03 = [
    {"name": "Stats", "icon": "stats.png", "visual": "stats.png",
     "copy": "CPU, memory, disk and network live in your menu bar. Finally find "
             "out which app is the reason your fans sound like a jet on the "
             "runway."},
    {"name": "AltTab", "icon": "alttab.png", "visual": "alttab.png",
     "copy": "Actual alt-tab for Mac: every window with a preview, not just apps. "
             "Pick the exact window you want instead of cycling past eleven of "
             "them."},
    KEIGO_EN,
    {"name": "MonitorControl", "icon": "monitorcontrol.png",
     "visual": "monitorcontrol.png",
     "copy": "Brightness and volume on your external monitor, from your Mac "
             "keyboard. Stop reaching behind the screen for that one cursed "
             "physical button."},
]

APPS_EN_04 = [
    {"name": "MeetingBar", "icon": "meetingbar.png", "visual": "meetingbar.png",
     "copy": "Your next meeting sits in the menu bar with a one-click join. No "
             "more digging through your calendar 40 seconds after it already "
             "started."},
    {"name": "Hand Mirror", "slug": "handmirror", "icon": "handmirror.png",
     "visual": "handmirror.png",
     "copy": "One click for a mirror before you join the call. Check the hair, "
             "check what is behind you, then walk in like you meant to look like "
             "that."},
    KEIGO_EN,
    {"name": "LocalSend", "icon": "localsend.png", "visual": "localsend.png",
     "copy": "Send files to any Mac, iPhone or Windows laptop on the same Wi-Fi. "
             "No account, no cloud, no emailing a zip to yourself like it is "
             "2011."},
]

APPS_EN_05 = [
    {"name": "Velja", "icon": "velja.png", "visual": "velja.png",
     "copy": "Choose which browser opens a link, or set rules so work links go to "
             "the work browser on their own. Two profiles, zero mixups."},
    {"name": "Keka", "icon": "keka.png", "visual": "keka.png",
     "copy": "Zip, 7z, rar, tar \u2014 compress and open all of it, password-protected "
             "included. The archive app you install once and never think about "
             "again."},
    KEIGO_EN,
    {"name": "CotEditor", "icon": "coteditor.png", "visual": "coteditor_en.png",
     "copy": "A fast native text editor for Mac. Syntax highlighting, find and "
             "replace, opens enormous files instantly. Perfect for everything too "
             "small to open an IDE for."},
]

APPS_EN_06 = [
    {"name": "Amphetamine", "icon": "amphetamine.png",
     "visual": "amphetamine_en.png",
     "copy": "Keep your Mac awake for exactly as long as you want. Downloads, "
             "renders and long uploads stop dying because the screen decided it "
             "was bedtime."},
    {"name": "Pure Paste", "slug": "purepaste", "icon": "purepaste.png",
     "visual": "purepaste.png",
     "copy": "Strips the formatting automatically when you paste. No more 14px "
             "Times New Roman turning up uninvited in the middle of your doc."},
    KEIGO_EN,
    {"name": "GrandPerspective", "icon": "grandperspective.png",
     "visual": "grandperspective.png",
     "copy": "Shows your whole disk as coloured blocks sized by what they take up. "
             "That 40GB you cannot account for is one folder you forgot about in "
             "2019."},
]

# ---------------------------------------------------------------- posts 007-012
# Eighteen more utilities, each used exactly once, none of them a writing tool
# (FORMAT-TESTS.md: ours is never compared against a competitor inside its own
# roundup). Every icon and card visual comes from the app's Mac App Store record;
# SOURCES.json pins the URL and hash. Plates repeat the 001-006 rotation on purpose:
# the hook has to stay identical across the series (PUBLISHING.md 6).
#
# No caption or card may call any of these free. Most are paid, and only ours carries
# a price note (PUBLISHING.md 6).

APPS_JA_07 = [
    {"name": "Dato", "icon": "dato.png", "visual": "dato.png",
     "copy": "メニューバーの時計に日付と予定を追加。海外の時間も並べて表示できるので、"
             "時差の計算をしなくて済む。"},
    {"name": "Klack", "icon": "klack.png", "visual": "klack.png",
     "copy": "キーを打つたびにメカニカルキーボードの打鍵音が鳴る。"
             "タイピングの手触りだけが変わる。"},
    APPS_JA[2],
    {"name": "ToothFairy", "icon": "toothfairy.png", "visual": "toothfairy.png",
     "copy": "AirPodsなどのBluetooth機器に、ワンクリックまたはショートカットで接続。"
             "バッテリー残量もメニューバーで確認できる。"},
]

APPS_JA_08 = [
    {"name": "Command X", "slug": "commandx", "icon": "commandx.png",
     "visual": "commandx.png",
     "copy": "Finderでファイルを⌘Xで切り取り、⌘Vで移動。"
             "コピーしてから元を消す手順がいらなくなる。"},
    {"name": "Permute", "icon": "permute.png", "visual": "permute.png",
     "copy": "動画・音声・画像をドラッグするだけで形式を変換。"
             "設定を覚える必要がない。"},
    APPS_JA[2],
    {"name": "Transloader", "icon": "transloader.png", "visual": "transloader.png",
     "copy": "iPhoneでリンクを送ると、Mac側でダウンロードが始まる。"
             "外出先で見つけたファイルを帰宅後に受け取れる。"},
]

APPS_JA_09 = [
    {"name": "Gifski", "icon": "gifski.png", "visual": "gifski.png",
     "copy": "動画を高画質なGIFに変換。画面録画をそのまま貼れる形にできる。"},
    {"name": "PDF Squeezer", "slug": "pdfsqueezer", "icon": "pdfsqueezer.png",
     "visual": "pdfsqueezer.png",
     "copy": "PDFのファイルサイズを圧縮。メールで送れないサイズの資料を"
             "まとめて軽くできる。"},
    APPS_JA[2],
    {"name": "Meta", "icon": "meta.png", "visual": "meta.png",
     "copy": "音楽ファイルのタイトルやアーティスト、アートワークを編集。"
             "取り込んだ曲の情報をまとめて整えられる。"},
]

APPS_JA_10 = [
    {"name": "Time Out", "slug": "timeout", "icon": "timeout.png",
     "visual": "timeout.png",
     "copy": "決めた間隔で画面をフェードさせて休憩を促す。"
             "気づいたら3時間ぶっ通し、を防げる。"},
    {"name": "HazeOver", "icon": "hazeover.png", "visual": "hazeover.png",
     "copy": "使っていないウインドウを暗くして、今見ている1枚だけを明るく保つ。"
             "画面が散らかっても集中が切れない。"},
    APPS_JA[2],
    {"name": "Plash", "icon": "plash.png", "visual": "plash.png",
     "copy": "好きなWebページをデスクトップの壁紙にできる。"
             "カレンダーやダッシュボードを常に表示しておける。"},
]

APPS_JA_11 = [
    {"name": "One Thing", "slug": "onething", "icon": "onething.png",
     "visual": "onething.png",
     "copy": "今やることを1つだけメニューバーに置く。"
             "気が散っても、画面の上を見れば戻ってこられる。"},
    {"name": "System Color Picker", "slug": "syscolorpicker",
     "icon": "syscolorpicker.png", "visual": "syscolorpicker.png",
     "copy": "macOS標準のカラーピッカーを単体アプリで。"
             "HEXやRGBをそのままコピーでき、履歴も残る。"},
    APPS_JA[2],
    {"name": "Charmstone", "icon": "charmstone.png", "visual": "charmstone.png",
     "copy": "よく使うアプリや操作をバーに固定して、どこからでも呼び出せる。"
             "Dockを探しに行く回数が減る。"},
]

APPS_JA_12 = [
    {"name": "Folder Peek", "slug": "folderpeek", "icon": "folderpeek.png",
     "visual": "folderpeek.png",
     "copy": "よく開くフォルダをメニューバーに固定。"
             "Finderを開かずに中のファイルをそのまま開ける。"},
    {"name": "Cardhop", "icon": "cardhop.png", "visual": "cardhop.png",
     "copy": "連絡先を検索窓に打ち込む感覚で扱える。"
             "登録も編集も、入力欄に一行書くだけで済む。"},
    APPS_JA[2],
    {"name": "Shareful", "icon": "shareful.png", "visual": "shareful.png",
     "copy": "macOSの共有メニューに「ファイルに保存」やコピーを追加。"
             "共有シートで毎回足りない項目を補える。"},
]

APPS_EN_07 = [
    {"name": "Dato", "icon": "dato.png", "visual": "dato.png",
     "copy": "Puts the date and your day into the menu bar clock, with other time "
             "zones lined up beside it. Stop doing timezone maths in your head "
             "before every call."},
    {"name": "Klack", "icon": "klack.png", "visual": "klack.png",
     "copy": "Every key you press makes a mechanical keyboard sound. It changes "
             "nothing about your Mac except how typing feels, which turns out to "
             "be the point."},
    KEIGO_EN,
    {"name": "ToothFairy", "icon": "toothfairy.png", "visual": "toothfairy.png",
     "copy": "Connect your AirPods with one click or one keystroke instead of "
             "digging through the Bluetooth menu, and see the battery level "
             "without asking."},
]

APPS_EN_08 = [
    {"name": "Command X", "slug": "commandx", "icon": "commandx.png",
     "visual": "commandx.png",
     "copy": "Cut and paste files in Finder the way you cut and paste text. Command "
             "X, Command V, done \u2014 no copy-then-delete-the-original dance."},
    {"name": "Permute", "icon": "permute.png", "visual": "permute.png",
     "copy": "Drag in a video, audio file or image and it converts to whatever "
             "format you needed. No presets to learn, no settings to get wrong."},
    KEIGO_EN,
    {"name": "Transloader", "icon": "transloader.png", "visual": "transloader.png",
     "copy": "Send a link from your phone and your Mac downloads it. The file is "
             "waiting on the desktop by the time you sit back down."},
]

APPS_EN_09 = [
    {"name": "Gifski", "icon": "gifski.png", "visual": "gifski.png",
     "copy": "Turns a video into a GIF that actually looks good. Screen recordings "
             "become something you can paste into a Slack thread."},
    {"name": "PDF Squeezer", "slug": "pdfsqueezer", "icon": "pdfsqueezer.png",
     "visual": "pdfsqueezer.png",
     "copy": "Shrinks PDFs that are too big to email, in batches, without turning "
             "the text into mush."},
    KEIGO_EN,
    {"name": "Meta", "icon": "meta.png", "visual": "meta.png",
     "copy": "Fixes the titles, artists and artwork on music files. For everything "
             "in your library that imported as Track 01 by Unknown Artist."},
]

APPS_EN_10 = [
    {"name": "Time Out", "slug": "timeout", "icon": "timeout.png",
     "visual": "timeout.png",
     "copy": "Fades the screen on a schedule so you actually take the break. It is "
             "harder to ignore than a notification, which is why it works."},
    {"name": "HazeOver", "icon": "hazeover.png", "visual": "hazeover.png",
     "copy": "Dims every window except the one you are working in. Your desktop "
             "can stay a mess and you will not notice."},
    KEIGO_EN,
    {"name": "Plash", "icon": "plash.png", "visual": "plash.png",
     "copy": "Makes any website your desktop wallpaper. A calendar, a dashboard, "
             "or something nice to look at behind your windows."},
]

APPS_EN_11 = [
    {"name": "One Thing", "slug": "onething", "icon": "onething.png",
     "visual": "onething.png",
     "copy": "Puts one single task in your menu bar. When you resurface from three "
             "unrelated tabs, it is still up there telling you what you were doing."},
    {"name": "System Color Picker", "slug": "syscolorpicker",
     "icon": "syscolorpicker.png", "visual": "syscolorpicker.png",
     "copy": "The macOS colour picker as a real app. Grab any colour on screen, "
             "copy it as hex or RGB, and keep a history of the ones you used."},
    KEIGO_EN,
    {"name": "Charmstone", "icon": "charmstone.png", "visual": "charmstone.png",
     "copy": "Pin the apps and actions you reach for constantly and fire them from "
             "anywhere. From the same developer as Rectangle."},
]

APPS_EN_12 = [
    {"name": "Folder Peek", "slug": "folderpeek", "icon": "folderpeek.png",
     "visual": "folderpeek.png",
     "copy": "Pin a folder to the menu bar and open what is inside without going "
             "to Finder first. Ideal for Downloads and whatever project you are on."},
    {"name": "Cardhop", "icon": "cardhop.png", "visual": "cardhop.png",
     "copy": "A contacts app you type at instead of click through. Search, add and "
             "edit people by writing one line into a box."},
    KEIGO_EN,
    {"name": "Shareful", "icon": "shareful.png", "visual": "shareful.png",
     "copy": "Adds Save to Files, Copy and more to the macOS share sheet. Fills in "
             "the options Apple left out of it."},
]

FORMAT = "must-have-apps"   # words for what FORMAT-TESTS.md registers as H5-CB

BASE = {"lang": "en", "format": FORMAT, "account": "en-ref",
        "handle": "@keigobutton", "plate": "_.jpeg",
        "hook": {"kicker": "my must have", "headline": "Macbook Apps"}}

# One base per posting account. The handle is burned into every card slide, so an
# account is a render dimension, not just a scheduling detail: the same post rendered
# for a different account is a different set of files.
BASE_JA = {"lang": "ja", "format": FORMAT, "account": "ruka",
           "handle": "@ruka_keigobutton", "plate": "_.jpeg",
           "hook": {"kicker": "MacBookに入れてよかった", "headline": "神アプリ4選"}}

BASE_JA_YUNA = {**BASE_JA, "account": "yuna", "handle": "@yuna_keigobutton"}

# The English campaign account. Handle chosen as the neutral brand handle rather than
# one of the Japanese personas: FORMAT-TESTS.md 1.5 records that flipping a
# JP-trained audience to English tests the algorithm rather than the format.
BASE_EN = {"lang": "en", "format": FORMAT, "account": "keigobutton",
           "handle": "@keigobutton", "plate": "_.jpeg",
           "hook": {"kicker": "no thoughts just", "headline": "MacBook Apps"}}

# For the in-screen series: ours shows the real overlay pill on the desktop, the other
# three get their own art as a floating window on that same desktop.
DESKTOPS = {
    "Ice": {"visual": "ice.png", "include_bar": False},
    "DockDoor": {"visual": "dockdoor.png", "include_bar": False},
    "KeigoButton": {"visual": None, "include_bar": True},
    "Dropover": {"visual": "dropover.png", "include_bar": False},
}

VARIANTS = {
    # Every slide is a plain flat card. Maximum consistency, zero new assets — but
    # our slide then carries no proof, and an icon cannot show what this app does.
    "en-flat": {**BASE, "post": "style-flat",
            "slides": [{"kind": "hook"}] + [
                {"kind": "card", **{k: v for k, v in a.items() if k != "visual"}}
                for a in APPS]},
    # Every slide is a card *with a visual inside it*. Still consistent, and every
    # app gets shown rather than described. This is the recommended one.
    "en-cards": {**BASE, "post": "style-cards",
            "slides": [{"kind": "hook"}] + [{"kind": "card", **a} for a in APPS]},
    # Japanese Phase 1 build for the existing app-discovery account. It keeps the
    # exact T1b visual system while localising the hook, benefits and product capture.
    "ja-001": {**BASE_JA, "post": "001_ice-dockdoor-keigo-dropover",
               "slides": ([{"kind": "hook"}] +
                          [{"kind": "card", **a} for a in APPS_JA])},
    "ja-002": {**BASE_JA, "plate": "Macbook Air M4 Sky Blue.jpeg",
               "post": "002_shottr-rectangle-keigo-maccy",
               "slides": ([{"kind": "hook"}] +
                          [{"kind": "card", **a} for a in APPS_JA_02])},
    "ja-003": {**BASE_JA, "plate": "Macbook ios ideas.jpeg",
               "post": "003_stats-alttab-keigo-monitorcontrol",
               "slides": ([{"kind": "hook"}] +
                          [{"kind": "card", **a} for a in APPS_JA_03])},
    "ja-004": {**BASE_JA, "plate": "summer.jpeg",
               "post": "004_meetingbar-handmirror-keigo-localsend",
               "slides": ([{"kind": "hook"}] +
                          [{"kind": "card", **a} for a in APPS_JA_04])},
    "ja-005": {**BASE_JA, "plate": "macbook wallpaper.jpeg",
               "post": "005_velja-keka-keigo-coteditor",
               "slides": ([{"kind": "hook"}] +
                          [{"kind": "card", **a} for a in APPS_JA_05])},
    "ja-006": {**BASE_JA, "plate": "_.jpeg",
               "post": "006_amphetamine-purepaste-keigo-grandperspective",
               "slides": ([{"kind": "hook"}] +
                          [{"kind": "card", **a} for a in APPS_JA_06])},
    "ja-007": {**BASE_JA, "plate": "_.jpeg",
               "post": "007_dato-klack-keigo-toothfairy",
               "slides": ([{"kind": "hook"}] +
                          [{"kind": "card", **a} for a in APPS_JA_07])},
    "ja-008": {**BASE_JA, "plate": "Macbook Air M4 Sky Blue.jpeg",
               "post": "008_commandx-permute-keigo-transloader",
               "slides": ([{"kind": "hook"}] +
                          [{"kind": "card", **a} for a in APPS_JA_08])},
    "ja-009": {**BASE_JA, "plate": "Macbook ios ideas.jpeg",
               "post": "009_gifski-pdfsqueezer-keigo-meta",
               "slides": ([{"kind": "hook"}] +
                          [{"kind": "card", **a} for a in APPS_JA_09])},
    "ja-010": {**BASE_JA, "plate": "summer.jpeg",
               "post": "010_timeout-hazeover-keigo-plash",
               "slides": ([{"kind": "hook"}] +
                          [{"kind": "card", **a} for a in APPS_JA_10])},
    "ja-011": {**BASE_JA, "plate": "macbook wallpaper.jpeg",
               "post": "011_onething-colorpicker-keigo-charmstone",
               "slides": ([{"kind": "hook"}] +
                          [{"kind": "card", **a} for a in APPS_JA_11])},
    "ja-012": {**BASE_JA, "plate": "_.jpeg",
               "post": "012_folderpeek-cardhop-keigo-shareful",
               "slides": ([{"kind": "hook"}] +
                          [{"kind": "card", **a} for a in APPS_JA_12])},
    # Our app alone as a screen composite. Kept for reference: it is the version
    # whose inconsistency made our slide read as the ad in someone else's roundup.
    "en-screen": {**BASE, "post": "style-screen",
            "slides": [{"kind": "hook"}] + [
                {"kind": "product" if a["name"] == "KeigoButton" else "card",
                 **{k: v for k, v in a.items() if k != "visual"},
                 **({"screenshot": "keigobutton.png"} if a["name"] == "KeigoButton" else {})}
                for a in APPS]},
}

# Every app demonstrated on the laptop screen, ours included — one desktop, one
# wallpaper, one Dock, four apps.
# Instagram runs on a different persona (yuna), so it needs its own render of the
# same three posts with the correct handle on the cards.
JA_POST_COUNT = 12

for _n in range(1, JA_POST_COUNT + 1):
    _src = VARIANTS[f"ja-{_n:03d}"]
    VARIANTS[f"ig-{_n:03d}"] = {**_src, **BASE_JA_YUNA,
                                "plate": _src["plate"], "post": _src["post"]}

# The English series. Same six plates, same six app lists and the same position 3 as
# ja-001..006, so a JP/EN comparison has one variable. Ours uses the English capture
# (`keigobutton.png` -> ../assets/bar.png), never the Japanese one.
EN_POSTS = [
    ("001_ice-dockdoor-keigo-dropover", "_.jpeg", APPS_EN_01),
    ("002_shottr-rectangle-keigo-maccy", "Macbook Air M4 Sky Blue.jpeg", APPS_EN_02),
    ("003_stats-alttab-keigo-monitorcontrol", "Macbook ios ideas.jpeg", APPS_EN_03),
    ("004_meetingbar-handmirror-keigo-localsend", "summer.jpeg", APPS_EN_04),
    ("005_velja-keka-keigo-coteditor", "macbook wallpaper.jpeg", APPS_EN_05),
    ("006_amphetamine-purepaste-keigo-grandperspective", "_.jpeg", APPS_EN_06),
    ("007_dato-klack-keigo-toothfairy", "_.jpeg", APPS_EN_07),
    ("008_commandx-permute-keigo-transloader", "Macbook Air M4 Sky Blue.jpeg", APPS_EN_08),
    ("009_gifski-pdfsqueezer-keigo-meta", "Macbook ios ideas.jpeg", APPS_EN_09),
    ("010_timeout-hazeover-keigo-plash", "summer.jpeg", APPS_EN_10),
    ("011_onething-colorpicker-keigo-charmstone", "macbook wallpaper.jpeg", APPS_EN_11),
    ("012_folderpeek-cardhop-keigo-shareful", "_.jpeg", APPS_EN_12),
]

for _n, (_post, _plate, _apps) in enumerate(EN_POSTS, start=1):
    VARIANTS[f"en-{_n:03d}"] = {
        **BASE_EN, "plate": _plate, "post": _post,
        "slides": [{"kind": "hook"}] + [{"kind": "card", **a} for a in _apps]}

# The English Instagram persona. Instagram is a different account from the English
# TikTok one, and the handle is burned into every card, so the same six posts need
# their own render — same rule as ig-001..006 on the Japanese side.
BASE_EN_HANNAH = {**BASE_EN, "account": "hannah", "handle": "@hannah_keigobutton"}

for _n in range(1, len(EN_POSTS) + 1):
    _src = VARIANTS[f"en-{_n:03d}"]
    VARIANTS[f"en-ig-{_n:03d}"] = {**_src, **BASE_EN_HANNAH,
                                   "plate": _src["plate"], "post": _src["post"]}

# Conversion-proof treatment. The roundup remains a five-slide H5-CB carousel;
# only KeigoButton's position-3 card changes. The visible "before" is rendered from
# the same Slack film set Format E uses, while the "after" is the real result-panel
# state from ../web/components/mac/components/product/Product.jsx. Keeping these as
# separate variant/output keys protects the published control renders.
PROOF_COPY = {
    "en": {
        "name": "KeigoButton",
        "before": "hey can we push tomorrows standup to 3, ill send the final deck too",
        "buttons": ["Polite", "Shorten", "Translate", "Soften"],
        "prompt": "Polite",
        "result": ("Could we move tomorrow’s standup to 3pm? I’ll send over the "
                   "final deck as well."),
        "description": ("Highlight text in Slack, Gmail, or Notion, press one of your "
                        "own AI buttons, and replace it in place—without tabbing out "
                        "to ChatGPT."),
        "before_label": "BEFORE",
        "after_label": "AFTER",
        "insert": "Insert",
    },
    "ja": {
        "name": "敬語ボタン",
        "before": "明日の定例、15時に変えてもらえますか？資料の最終版も送ります。",
        "buttons": ["敬語", "要約", "英訳", "丁寧に"],
        "prompt": "敬語",
        "result": ("恐れ入りますが、明日の定例を15時からに変更いただけますでしょうか。"
                   "あわせて資料の最終版も共有いたします。"),
        "description": ("Slackやメールで文章を選び、ボタンを押すだけ。敬語・要約・英訳などを、"
                        "今いるアプリを離れずに実行できます。"),
        "before_label": "変更前",
        "after_label": "変更後",
        "insert": "挿入",
    },
}


def proof_slides(source):
    """Replace only the KeigoButton card; every other test variable stays fixed."""
    slides = []
    for slide in source["slides"]:
        if slide.get("slug") == "keigobutton" or slide.get("name") == "KeigoButton":
            slides.append({
                "kind": "proof", "slug": "keigobutton",
                "name": PROOF_COPY[source["lang"]]["name"],
                "icon": "keigobutton.png",
            })
        else:
            slides.append(dict(slide))
    return slides


for _prefix, _count in (("ja", JA_POST_COUNT), ("ig", JA_POST_COUNT),
                        ("en", len(EN_POSTS)), ("en-ig", len(EN_POSTS))):
    for _n in range(1, _count + 1):
        _source = VARIANTS[f"{_prefix}-{_n:03d}"]
        VARIANTS[f"{_prefix}-proof-{_n:03d}"] = {
            **_source,
            "post": f"proof_{_source['post']}",
            "slides": proof_slides(_source),
        }

VARIANTS["en-inscreen"] = {**BASE, "post": "style-inscreen",
                   "slides": [{"kind": "hook"}] + [
                       {"kind": "product", "name": a["name"], "icon": a["icon"],
                        "copy": a["copy"], "visual": a["visual"],
                        "desktop": DESKTOPS[a["name"]]}
                       for a in APPS]}

VARIANT = VARIANTS["ja-001"]

# ---------------------------------------------------------------- css

CSS = f"""
@font-face {{ font-family:'Poppins'; src:url('{FONTS}/Poppins-ExtraBold.ttf'); font-weight:800; }}
@font-face {{ font-family:'Script';  src:url('{FONTS}/DancingScript.ttf'); }}
@font-face {{ font-family:'Inter';   src:url('{FONTS}/Inter.ttf'); }}

* {{ margin:0; padding:0; box-sizing:border-box; }}
html, body {{ width:{W}px; height:{H}px; overflow:hidden; background:#000; }}
.stage {{ position:relative; width:{W}px; height:{H}px; }}
.stage img.layer {{ position:absolute; inset:0; width:{W}px; height:{H}px; object-fit:cover; }}

/* --- hook ------------------------------------------------------------ */
.fan {{ position:absolute; left:0; right:0; display:flex; justify-content:center;
        align-items:flex-end; transform-origin:50% 100%; }}
.fan img {{ transform-origin:50% 100%;
            filter:drop-shadow(0 18px 34px rgba(0,0,0,.55)); }}
.hook-text {{ position:absolute; left:0; right:0; text-align:center;
              display:flex; flex-direction:column; justify-content:center; }}
.kicker {{ font-family:'Script'; font-size:76px; color:#fff; line-height:1;
           text-shadow:0 4px 20px rgba(0,0,0,.5); }}
.headline {{ font-family:'Poppins'; font-weight:800; font-size:116px; color:#fff;
             line-height:1; letter-spacing:-.02em;
             text-shadow:0 6px 26px rgba(0,0,0,.55); }}

/* --- flat card ------------------------------------------------------- */
.card-icon {{ position:absolute; left:50%; transform:translateX(-50%);
              width:284px; height:284px;
              filter:drop-shadow(0 22px 40px rgba(0,0,0,.5)); }}
.card {{ position:absolute; left:50%; transform:translateX(-50%);
         width:824px; background:#fff; border-radius:0 30px 30px 30px;
         padding:64px 62px 54px; text-align:center;
         box-shadow:0 30px 70px rgba(0,0,0,.45); }}
.shot {{ width:700px; height:340px; object-fit:cover; border-radius:16px;
         display:block; margin:0 auto 38px;
         box-shadow:0 10px 26px rgba(0,0,0,.18); }}
.tab {{ position:absolute; top:-54px; left:0; width:214px; height:56px;
        background:#fff; border-radius:20px 20px 0 0; display:flex;
        align-items:center; gap:11px; padding-left:26px; }}
.dot {{ width:19px; height:19px; border-radius:50%; }}
.card h2 {{ font-family:'Inter'; font-weight:600; font-size:56px; color:#111;
            margin-bottom:30px; letter-spacing:-.01em; }}
.card p {{ font-family:'Inter'; font-weight:400; font-size:32px; line-height:1.52;
           color:#2b2b2b; }}
.handle {{ font-family:'Inter'; font-size:27px; color:#8a8a8a; margin-top:34px; }}

/* Japanese is a separate campaign, not English copy forced through the display
   fonts. Hiragino ships with macOS and gives the dense headline and body natural
   metrics; Latin app names continue to fall through cleanly. */
.ja .kicker {{ font-family:'Hiragino Sans','Yu Gothic',sans-serif; font-weight:700;
               font-size:58px; letter-spacing:.01em; }}
.ja .headline {{ font-family:'Hiragino Sans','Yu Gothic',sans-serif; font-weight:800;
                 font-size:112px; letter-spacing:-.04em; }}
.ja .card h2, .ja .card p, .ja .handle {{
  font-family:'Hiragino Sans','Yu Gothic','Inter',sans-serif;
}}
.ja .card p {{ font-size:31px; line-height:1.62; }}

/* --- conversion-proof card ------------------------------------------ */
.proof-icon {{ position:absolute; left:50%; top:54px; transform:translateX(-50%);
               width:190px; height:190px;
               filter:drop-shadow(0 20px 36px rgba(0,0,0,.48)); }}
.proof-card {{ position:absolute; left:50%; top:270px; transform:translateX(-50%);
               width:824px; padding:42px 62px 38px; text-align:center;
               background:#fff; border-radius:0 30px 30px 30px;
               box-shadow:0 30px 70px rgba(0,0,0,.45); }}
.proof-card h2 {{ font-family:'Inter'; font-weight:600; font-size:52px; line-height:1.1;
                  color:#111; margin-bottom:26px; letter-spacing:-.015em; }}
.proof-grid {{ display:grid; grid-template-rows:repeat(2,270px); gap:18px; width:700px; }}
.proof-state {{ position:relative; overflow:hidden; border-radius:18px; background:#f5f4f2;
                border:1px solid #dededc; text-align:left; }}
.proof-state::before {{ content:''; position:absolute; inset:0 0 auto; height:8px;
                        background:#4a154b; }}
.proof-state__label {{ position:absolute; left:18px; top:16px; z-index:4;
                       display:inline-flex; align-items:center; gap:8px;
                       padding:6px 12px 6px 7px; border-radius:9999px;
                       background:#4a154b; color:#fff; box-shadow:0 3px 8px rgba(74,21,75,.2);
                       font-family:'Inter'; font-size:15px; font-weight:800;
                       letter-spacing:.06em; }}
.proof-state__label b {{ display:inline-flex; align-items:center; justify-content:center;
                         width:21px; height:21px; border-radius:50%; background:#fff;
                         color:#4a154b; font-size:13px; letter-spacing:0; }}
.proof-state__app {{ position:absolute; right:22px; top:20px; display:inline-flex;
                     align-items:center; gap:8px; font-family:'Inter'; font-size:17px;
                     font-weight:600; color:#6a6967; }}
.proof-state__app i {{ width:11px; height:11px; border-radius:3px; background:#4a154b; }}
.proof-input {{ position:absolute; left:24px; right:24px; top:62px; min-height:122px;
                padding:22px 24px 48px; border-radius:14px; background:#fff;
                border:1.5px solid #c9c9cb; box-shadow:0 3px 10px rgba(0,0,0,.07);
                font-family:'Inter'; font-size:23px; line-height:1.38; color:#1d1c1d; }}
.proof-input__tools {{ position:absolute; left:22px; bottom:13px; display:flex; gap:15px;
                       font-size:16px; color:#8d8d8e; }}
.proof-bar {{ --barscale:1.18; position:absolute; z-index:3; left:50%; bottom:22px;
              transform:translateX(-50%); display:inline-flex; align-items:center;
              gap:calc(2px * var(--barscale)); height:calc(34px * var(--barscale));
              padding:0 calc(8px * var(--barscale)); border-radius:9999px;
              background:#141312; border:1px solid #2e2b28;
              box-shadow:0 9px 26px rgba(10,9,8,.34); white-space:nowrap; }}
.proof-bar__mark {{ display:block; width:calc(16px * var(--barscale));
                    height:calc(16px * var(--barscale)); flex:none; }}
.proof-bar__rule {{ width:1px; align-self:stretch; margin:calc(7px * var(--barscale)) calc(6px * var(--barscale));
                    background:#2e2b28; flex:none; }}
.proof-bar__button {{ display:inline-flex; align-items:center; justify-content:center;
                      height:calc(22px * var(--barscale)); padding:0 calc(10px * var(--barscale));
                      border-radius:9999px; font-family:'Inter';
                      font-size:calc(12px * var(--barscale)); font-weight:500;
                      line-height:1; color:#fdfcfc; }}
.proof-bar__button--hot {{ position:relative; background:#2e2b28; color:#fdfcfc;
                           font-weight:700; box-shadow:inset 0 0 0 1px rgba(255,255,255,.04); }}
.proof-click-pointer {{ position:absolute; z-index:6; left:82%; top:58%;
                        width:25px; height:29px; overflow:visible;
                        filter:drop-shadow(0 2px 2px rgba(0,0,0,.45)); }}
.proof-bar__pencil {{ color:#a59f97; padding:0 calc(8px * var(--barscale)); }}
.proof-bar__pencil svg {{ display:block; width:calc(14px * var(--barscale));
                          height:calc(14px * var(--barscale)); }}
.proof-description {{ width:700px; margin:22px auto 0; color:#2b2b2b;
                      font-family:'Inter'; font-size:23px; font-weight:400;
                      line-height:1.42; letter-spacing:-.01em; text-align:center; }}
.proof-card .handle {{ margin-top:17px; }}

/* Exact dark ramp and geometry used by the web recreation of the shipped result
   panel. At --pscale:1.5 the controls remain legible in a 1080px carousel. */
.proof-result {{ --pscale:1.18; position:absolute; z-index:3; left:50%; bottom:12px;
                 transform:translateX(-50%);
                 width:calc(300px * var(--pscale)); overflow:hidden; display:flex;
                 flex-direction:column; color:#fdfcfc; text-align:left;
                 border-radius:calc(14px * var(--pscale)); background:#141312;
                 border:1px solid #2e2b28;
                 box-shadow:0 16px 42px -6px rgba(10,9,8,.48),0 4px 12px rgba(10,9,8,.28); }}
.proof-result__head {{ display:flex; align-items:center; justify-content:space-between;
                       padding:calc(9px * var(--pscale)) calc(12px * var(--pscale));
                       border-bottom:1px solid #2e2b28; }}
.proof-result__pager {{ display:inline-flex; align-items:center; gap:calc(8px * var(--pscale));
                        font-family:'Inter'; font-size:calc(11px * var(--pscale));
                        color:#a59f97; }}
.proof-result__chev,.proof-result__x {{ color:#777169; }}
.proof-result__prompt {{ margin:calc(10px * var(--pscale)) calc(12px * var(--pscale)) 0;
                         padding:calc(7px * var(--pscale)) calc(10px * var(--pscale));
                         border-radius:calc(10px * var(--pscale)); background:#1e1c1a;
                         border:1px solid #2e2b28; font-family:'Inter';
                         font-size:calc(11px * var(--pscale)); color:#a59f97; }}
.proof-result__body {{ padding:calc(12px * var(--pscale)); font-family:'Inter';
                       font-size:calc(13px * var(--pscale)); line-height:1.5; color:#fdfcfc; }}
.proof-result__foot {{ display:flex; align-items:center; justify-content:space-between;
                       gap:calc(10px * var(--pscale)); padding:calc(9px * var(--pscale)) calc(12px * var(--pscale));
                       border-top:1px solid #2e2b28; background:#141312; }}
.proof-result__tools {{ display:inline-flex; align-items:center; gap:calc(10px * var(--pscale));
                        color:#777169; }}
.proof-result__tools svg {{ width:calc(14px * var(--pscale)); height:calc(14px * var(--pscale)); }}
.proof-result__insert {{ display:inline-flex; align-items:center; gap:calc(6px * var(--pscale));
                         height:calc(24px * var(--pscale)); padding:0 calc(12px * var(--pscale));
                         border-radius:9999px; background:#fdfcfc; color:#141312;
                         font-family:'Inter'; font-size:calc(11px * var(--pscale));
                         font-weight:500; white-space:nowrap; }}
.ja .proof-card h2,.ja .proof-state,.ja .proof-result,.ja .proof-description {{
  font-family:'Hiragino Sans','Yu Gothic','Inter',sans-serif;
}}

/* --- product (screen composite) -------------------------------------- */
.prod {{ position:absolute; left:56px; top:58px; right:56px; display:flex; gap:30px; }}
.prod img {{ width:136px; height:136px; flex:none;
             filter:drop-shadow(0 14px 28px rgba(0,0,0,.6)); }}
.prod h2 {{ font-family:'Poppins'; font-weight:800; font-size:62px; color:#fff;
            line-height:1; letter-spacing:-.02em; margin-bottom:18px; }}
.prod p {{ font-family:'Inter'; font-weight:400; font-size:30px; line-height:1.45;
           color:rgba(255,255,255,.93); }}
"""


def page(body, lang="en"):
    return (f"<!doctype html><html lang='{esc(lang)}'><head><meta charset='utf-8'>"
            f"<style>{CSS}</style></head><body class='{esc(lang)}'>{body}</body></html>")


def esc(s):
    return html.escape(s)


# ---------------------------------------------------------------- slides

def hook_html(plate_file, lid, icons, kicker, headline, lang="en"):
    (x1, y1), (x2, y2) = lid
    # Redraw only the physical lid in front of the icon fan. The old mask extended
    # the top edge to both canvas margins and centred the fan on the canvas; on an
    # off-centre MacBook that clipped an icon against an imaginary edge outside the
    # laptop. Both the fan and its occluder now use the measured lid endpoints.
    clip = (f"polygon({x1}px {y1}px, {x2}px {y2}px, "
            f"{x2}px {H}px, {x1}px {H}px)")
    # Fan the icons on an arc: angle grows linearly from the centre, drop grows
    # quadratically, so the inner icons stand tallest above the lid and the outer
    # ones tuck further behind it — the shape both reference hooks use.
    n = len(icons)
    lid_angle = math.degrees(math.atan2(y2 - y1, x2 - x1))
    icon_px = fan_icon_px(x2 - x1, n)
    margin = -icon_px * ICON_OVERLAP / 2
    fan = ""
    for k, ic in enumerate(icons):
        pos = k - (n - 1) / 2
        angle = pos * 9.0
        drop = 13.0 * (icon_px / 182) * pos ** 2   # arc scales with the icons
        fan += (f"<img src='{ICONS}/{ic}' style='width:{icon_px}px;height:{icon_px}px;"
                f"margin:0 {margin:.1f}px;"
                f"transform:translateY({drop:.1f}px) rotate({angle:.1f}deg)'>")
    # Keep the entire fan parallel to the real lid. Anchoring a horizontal fan to
    # min(y) buried the left and right icons by different amounts on tilted photos,
    # leaving the row visually detached even though the mask itself was correct.
    lid_mid_y = (y1 + y2) / 2
    fan_bottom = H - (lid_mid_y + 62)
    # The title is centred in the gap between a fixed top inset and the fan, rather
    # than pinned to a fixed top. A fixed inset has to be tuned per photo: the lid
    # sits at y=396 on one plate and y=470 on another, so one number is either
    # cramped at the top or colliding with the icons. Centring makes the padding a
    # consequence of the measured lid.
    fan_top = (H - fan_bottom) - icon_px
    text_top = 56
    text_height = max(120, fan_top - text_top - 28)
    return page(f"""
<div class='stage'>
  <img class='layer' src='{PLATES}/{plate_file}'>
  <div class='fan' style='left:{x1}px;right:auto;width:{x2 - x1}px;
       bottom:{fan_bottom:.1f}px;transform:rotate({lid_angle:.3f}deg)'>{fan}</div>
  <img class='layer' src='{PLATES}/{plate_file}' style='clip-path:{clip}'>
  <div class='hook-text' style='top:{text_top}px;height:{text_height:.0f}px'>
    <div class='kicker'>{esc(kicker)}</div>
    <div class='headline' style='margin-top:8px'>{esc(headline)}</div>
  </div>
</div>""", lang)


def card_html(name, icon, copy, handle, visual=None, lang="en"):
    # A visual makes the card taller, so the icon and card both ride up. The block
    # sits high in the frame on purpose: the copy runs 3-4 lines depending on the app,
    # so the slack has to live at the bottom where a varying card height absorbs it
    # invisibly, rather than at the top where it would shift the icon between slides.
    icon_top, card_top, icon_px = (100, 374, 224) if visual else (268, 604, 284)
    shot = f"<img class='shot' src='{SHOTS}/{visual}'>" if visual else ""
    copy_html = "<br>".join(esc(line) for line in copy) if isinstance(copy, list) else esc(copy)
    return page(f"""
<div class='stage'>
  <img class='layer' src='{PLATES}/backdrop_dark.png'>
  <img class='card-icon' src='{ICONS}/{icon}' style='top:{icon_top}px;width:{icon_px}px;height:{icon_px}px'>
  <div class='card' style='top:{card_top}px'>
    {shot}
    <div class='tab'>
      <div class='dot' style='background:#ff5f57'></div>
      <div class='dot' style='background:#febc2e'></div>
      <div class='dot' style='background:#28c840'></div>
    </div>
    <h2>{esc(name)}</h2>
    <p>{copy_html}</p>
    <div class='handle'>{esc(handle)}</div>
  </div>
</div>""", lang)


def product_html(plate_file, name, icon, copy, lang="en"):
    return page(f"""
<div class='stage'>
  <img class='layer' src='{PLATES}/{plate_file}'>
  <div class='prod'>
    <img src='{ICONS}/{icon}'>
    <div><h2>{esc(name)}</h2><p>{esc(copy)}</p></div>
  </div>
</div>""", lang)


def result_tools_html():
    """The same regenerate/copy/feedback glyphs Product.jsx puts in the footer."""
    return """
<svg viewBox='0 0 16 16' fill='none' stroke='currentColor' stroke-width='1.4'
     stroke-linecap='round' stroke-linejoin='round' aria-hidden='true'>
  <path d='M13.5 8a5.5 5.5 0 1 1-1.6-3.9'/><path d='M13.5 2.5V6H10'/>
</svg>
<svg viewBox='0 0 16 16' fill='none' stroke='currentColor' stroke-width='1.4'
     stroke-linejoin='round' aria-hidden='true'>
  <rect x='5.5' y='5.5' width='8' height='8' rx='1.6'/>
  <path d='M10.5 3.2A1.7 1.7 0 0 0 8.8 2.5H4.2A1.7 1.7 0 0 0 2.5 4.2v4.6c0 .7.4 1.3 1 1.6'/>
</svg>
<svg viewBox='0 0 16 16' fill='none' stroke='currentColor' stroke-width='1.4'
     stroke-linejoin='round' aria-hidden='true'>
  <path d='M5.5 14V6.8l3-4.3c.9 0 1.6.8 1.5 1.7L9.7 6.5h3.1c.9 0 1.6.9 1.4 1.8l-.9 4.3c-.1.8-.8 1.4-1.6 1.4z'/>
  <rect x='1.6' y='6.8' width='3' height='7.2' rx='1'/>
</svg>
<svg style='transform:rotate(180deg)' viewBox='0 0 16 16' fill='none'
     stroke='currentColor' stroke-width='1.4' stroke-linejoin='round' aria-hidden='true'>
  <path d='M5.5 14V6.8l3-4.3c.9 0 1.6.8 1.5 1.7L9.7 6.5h3.1c.9 0 1.6.9 1.4 1.8l-.9 4.3c-.1.8-.8 1.4-1.6 1.4z'/>
  <rect x='1.6' y='6.8' width='3' height='7.2' rx='1'/>
</svg>"""


def proof_html(icon, handle, lang="en"):
    copy = PROOF_COPY[lang]
    click_pointer = """
<svg class='proof-click-pointer' viewBox='0 0 26 30' aria-hidden='true'>
  <path d='M2.2 1.8 3.8 23l5.1-4.6 4.1 9.3 4.3-1.9-4.1-9.1 6.9-.2z'
        fill='#fff' stroke='#111' stroke-width='1.8' stroke-linejoin='round'/>
</svg>"""
    buttons = "".join(
        f"<span class='proof-bar__button{' proof-bar__button--hot' if i == 0 else ''}'>"
        f"{esc(label)}{click_pointer if i == 0 else ''}</span>" for i, label in enumerate(copy["buttons"])
    )
    pencil = """
<svg viewBox='0 0 16 16' fill='none' stroke='currentColor' stroke-width='1.4'
     stroke-linecap='round' stroke-linejoin='round' aria-hidden='true'>
  <path d='M11.3 2.7a1.7 1.7 0 0 1 2.4 2.4L5.5 13.3 2 14l.7-3.5z'/>
</svg>"""
    state = f"""
<div class='proof-input'>{esc(copy['before'])}
  <span class='proof-input__tools'><b>B</b><i>I</i><s>S</s><span>↗</span></span>
</div>"""
    return page(f"""
<div class='stage'>
  <img class='layer' src='{PLATES}/backdrop_dark.png'>
  <img class='proof-icon' src='{ICONS}/{icon}'>
  <div class='proof-card'>
    <div class='tab'>
      <div class='dot' style='background:#ff5f57'></div>
      <div class='dot' style='background:#febc2e'></div>
      <div class='dot' style='background:#28c840'></div>
    </div>
    <h2>{esc(copy['name'])}</h2>
    <div class='proof-grid'>
      <div class='proof-state'>
        <span class='proof-state__label'><b>1</b>{esc(copy['before_label'])}</span>
        <span class='proof-state__app'><i></i>Slack</span>
        {state}
        <div class='proof-bar'>
          <img class='proof-bar__mark' src='{WEB_MARK}'>
          <span class='proof-bar__rule'></span>{buttons}<span class='proof-bar__rule'></span>
          <span class='proof-bar__pencil'>{pencil}</span>
        </div>
      </div>
      <div class='proof-state'>
        <span class='proof-state__label'><b>2</b>{esc(copy['after_label'])}</span>
        <span class='proof-state__app'><i></i>Slack</span>
        {state}
        <div class='proof-result'>
          <div class='proof-result__head'>
            <span class='proof-result__pager'><span class='proof-result__chev'>‹</span>
              <span>1 / 3</span><span class='proof-result__chev'>›</span></span>
            <span class='proof-result__x'>✕</span>
          </div>
          <div class='proof-result__prompt'>{esc(copy['prompt'])}</div>
          <div class='proof-result__body'>{esc(copy['result'])}</div>
          <div class='proof-result__foot'>
            <span class='proof-result__tools'>{result_tools_html()}</span>
            <span class='proof-result__insert'>{esc(copy['insert'])} <span>↵</span></span>
          </div>
        </div>
      </div>
    </div>
    <p class='proof-description'>{esc(copy['description'])}</p>
    <div class='handle'>{esc(handle)}</div>
  </div>
</div>""", lang)


# ---------------------------------------------------------------- placeholder

def make_placeholder(path, size=(2560, 1600)):
    """An obvious wireframe, so the composition can be judged without pretending
    to be a real capture. Replaced by the real screenshot when it arrives."""
    im = Image.new("RGB", size, (232, 233, 236))
    d = ImageDraw.Draw(im)
    w, h = size
    d.rectangle([0, 0, w, 64], fill=(214, 216, 220))                  # menu bar
    d.rounded_rectangle([w * .17, 190, w * .83, h * .74], 26,
                        fill=(255, 255, 255), outline=(198, 200, 206), width=4)
    for i in range(7):                                                 # text lines
        y = h * .30 + i * 74
        d.rounded_rectangle([w * .21, y, w * .21 + (520 if i % 3 else 900), y + 26],
                            13, fill=(219, 221, 226))
    d.rounded_rectangle([w * .34, h * .845, w * .66, h * .845 + 96], 48,
                        fill=(30, 30, 34))                             # overlay bar
    d.rectangle([0, h - 84, w, h], fill=(206, 208, 213))               # dock
    for i, lbl in enumerate(["PLACEHOLDER", "full-screen capture goes here"]):
        d.text((w * .5 - 150 + i * 0, h * .13 + i * 46), lbl, fill=(150, 60, 60))
    im.save(path)


# ---------------------------------------------------------------- driver

def shoot(html_text, out_path, tag):
    WORK.mkdir(parents=True, exist_ok=True)
    src = WORK / f"{tag}.html"
    src.write_text(html_text)
    subprocess.run([
        CHROME, "--headless", "--disable-gpu", "--hide-scrollbars",
        "--allow-file-access-from-files", "--force-device-scale-factor=1",
        f"--window-size={W},{H}", f"--screenshot={out_path}", f"file://{src}",
    ], check=True, capture_output=True)


# (source, crop anchor). Ours anchors to the bottom because a centre crop drops the
# button bar, which is the only thing on that screenshot a viewer needs to see.
VISUAL_SOURCES = {
    "ice.png": ("shots_probe/ice_banner.png", "center"),
    "dockdoor.png": ("shots_probe/dockdoor_hero.png", "center"),
    "dropover.png": ("shots_probe/dropover_tile-instant-actions.jpg", "center"),
    "keigobutton.png": ("../assets/bar.png", "center"),
    "keigobutton_ja.png": ("../assets/bar_jap.png", "center"),
    "shottr.png": ("source-assets/apps/shottr/visual.jpg", "center"),
    "rectangle.png": ("source-assets/apps/rectangle/visual.jpg", "center"),
    "maccy.png": ("source-assets/apps/maccy/visual.png", "center"),
    "stats.png": ("source-assets/apps/stats/visual.webp", "center"),
    "alttab.png": ("source-assets/apps/alttab/visual.webp", "center"),
    "monitorcontrol.png": ("source-assets/apps/monitorcontrol/visual.png", "center"),
    "meetingbar.png": ("source-assets/apps/meetingbar/visual.jpg", "top"),
    "handmirror.png": ("source-assets/apps/handmirror/visual.jpg", "top"),
    "localsend.png": ("source-assets/apps/localsend/visual.png", "center"),
    "velja.png": ("source-assets/apps/velja/visual.jpg", "top"),
    "keka.png": ("source-assets/apps/keka/visual.jpg", "top"),
    "coteditor.png": ("source-assets/apps/coteditor/visual.jpg", "top"),
    "amphetamine.png": ("source-assets/apps/amphetamine/visual.jpg", "top"),
    # The Japanese campaign's Amphetamine and CotEditor art is from the JP storefront
    # and shows a Japanese UI. Same composition, US storefront, for the English cards.
    "amphetamine_en.png": ("source-assets/apps/amphetamine/visual_en.jpg", "top"),
    "coteditor_en.png": ("source-assets/apps/coteditor/visual_en.jpg", "top"),
    "purepaste.png": ("source-assets/apps/purepaste/visual.jpg", "center"),
    "grandperspective.png": ("source-assets/apps/grandperspective/visual.jpg", "center"),
    # posts 007-012. All Mac App Store art at 800x500, so a centre crop keeps the
    # window in frame; the four that only ship portrait screenshots were dropped
    # rather than squeezed (see FORMAT-TESTS.md).
    "dato.png": ("source-assets/apps/dato/visual.jpg", "center"),
    "klack.png": ("source-assets/apps/klack/visual.jpg", "center"),
    "toothfairy.png": ("source-assets/apps/toothfairy/visual.jpg", "center"),
    "commandx.png": ("source-assets/apps/commandx/visual.jpg", "center"),
    "permute.png": ("source-assets/apps/permute/visual.jpg", "center"),
    "transloader.png": ("source-assets/apps/transloader/visual.jpg", "center"),
    "gifski.png": ("source-assets/apps/gifski/visual.jpg", "center"),
    "pdfsqueezer.png": ("source-assets/apps/pdfsqueezer/visual.jpg", "center"),
    "meta.png": ("source-assets/apps/meta/visual.jpg", "center"),
    "timeout.png": ("source-assets/apps/timeout/visual.jpg", "center"),
    "hazeover.png": ("source-assets/apps/hazeover/visual.jpg", "center"),
    "plash.png": ("source-assets/apps/plash/visual.jpg", "center"),
    "onething.png": ("source-assets/apps/onething/visual.jpg", "center"),
    "syscolorpicker.png": ("source-assets/apps/syscolorpicker/visual.jpg", "center"),
    "charmstone.png": ("source-assets/apps/charmstone/visual.jpg", "center"),
    "folderpeek.png": ("source-assets/apps/folderpeek/visual.jpg", "center"),
    "cardhop.png": ("source-assets/apps/cardhop/visual.jpg", "center"),
    "shareful.png": ("source-assets/apps/shareful/visual.jpg", "center"),
}


def prepare_visuals(slides):
    SHOTS.mkdir(exist_ok=True)
    missing = []
    for s_ in slides:
        v = s_.get("visual")
        if not v:
            continue
        rel, focus = VISUAL_SOURCES.get(v, ("", "center"))
        src = ROOT / rel
        if src.exists():
            plates.fit_visual(src, SHOTS / v, focus=focus)
        elif not (SHOTS / v).exists():
            missing.append(v)
    if missing:
        raise SystemExit(f"missing card visuals: {missing}")


def main():
    global VARIANT
    if len(sys.argv) > 1 and sys.argv[1] in ("--list", "-l"):
        for k, v in VARIANTS.items():
            print(f"  {k:12s} -> out/{v['lang']}/{v['format']}/"
                  f"{v.get('account','default')}/{v['post']}")
        return 0
    if len(sys.argv) > 1:
        if sys.argv[1] not in VARIANTS:
            raise SystemExit(f"unknown variant {sys.argv[1]}; pick from {list(VARIANTS)}")
        VARIANT = VARIANTS[sys.argv[1]]
    if not pathlib.Path(CHROME).exists():
        raise SystemExit(f"Chrome not found at {CHROME}")
    OUT.mkdir(exist_ok=True)
    prepare_visuals(VARIANT["slides"])
    PLATES.mkdir(exist_ok=True)
    variant_out = (OUT / VARIANT["lang"] / VARIANT["format"]
                   / VARIANT.get("account", "default") / VARIANT["post"])
    variant_out.mkdir(parents=True, exist_ok=True)
    for stale in variant_out.glob("*.png"):
        stale.unlink()

    plate_name = VARIANT["plate"]
    plate, meta = plates.load_plate(plate_name)
    stem = pathlib.Path(plate_name).stem.replace(" ", "_")
    bar_src = ROOT.parent / "assets" / "bar.png"

    # Each product slide gets its own screen composite.
    prod_plates = {}
    for slide in VARIANT["slides"]:
        if slide["kind"] != "product":
            continue
        spec = slide.get("desktop")
        if spec is None:
            raise SystemExit(f"{slide['name']}: product slide needs a desktop spec")
        if not bar_src.exists():
            raise SystemExit(f"missing {bar_src}")
        vis = SHOTS / spec["visual"] if spec.get("visual") else None
        screen = plates.desktop_plate(bar_src, visual=vis,
                                      include_bar=spec["include_bar"])
        tmp = PLATES / f"screen_{slide['name'].lower()}.png"
        screen.save(tmp)
        composed = plates.composite_screen(plate, meta["screen"], tmp)
        name = f"{stem}__{slide['name'].lower()}.png"
        composed.save(PLATES / name)
        prod_plates[slide["name"]] = name

    icons = list(dict.fromkeys(
        s["icon"] for s in VARIANT["slides"] if s.get("icon")
    ))
    vid = VARIANT["post"]

    for n, slide in enumerate(VARIANT["slides"], start=1):
        slug = slide.get("slug", slide.get("name", "hook").lower())
        out = variant_out / f"{n:02d}_{slug}.png"
        if slide["kind"] == "hook":
            doc = hook_html(f"{stem}.png", meta["lid"], icons,
                            VARIANT["hook"]["kicker"], VARIANT["hook"]["headline"],
                            VARIANT["lang"])
        elif slide["kind"] == "card":
            doc = card_html(slide["name"], slide["icon"], slide["copy"],
                            VARIANT["handle"], slide.get("visual"), VARIANT["lang"])
        elif slide["kind"] == "proof":
            doc = proof_html(slide["icon"], VARIANT["handle"], VARIANT["lang"])
        else:
            doc = product_html(prod_plates[slide["name"]], slide["name"],
                               slide["icon"], slide["copy"], VARIANT["lang"])
        shoot(doc, out, f"{vid}_{n:02d}")
        print(f"  {out.relative_to(ROOT)}")

    shutil.rmtree(WORK, ignore_errors=True)
    try:
        WORK.parent.rmdir()
    except OSError:
        pass
    print(f"\n{len(VARIANT['slides'])} slides -> {variant_out.relative_to(ROOT.parent)}")


if __name__ == "__main__":
    sys.exit(main())
