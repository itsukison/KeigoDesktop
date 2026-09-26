import DesktopRewriteKit

enum ReleaseHighlights {
    // Change this only when shipping a new introduction, not for every patch build.
    static let id = "desktop-four-position-bar"
    static let features: [ReleaseFeature] = [.placement]
}

enum ReleaseFeature: String, Identifiable {
    case buttons, placement, reply
    var id: String { rawValue }

    var label: String {
        switch self {
        case .buttons: return tr("よく使う指示をボタンに", "Your own writing buttons", "常用指令，一键直达")
        case .placement: return tr("好きな場所に", "At home on your screen", "放在顺手的位置")
        case .reply: return tr("コピーから返信", "From copy to reply", "复制，即可回复")
        }
    }

    var title: String {
        switch self {
        case .buttons: return tr("いつもの指示を、\nワンクリックで。", "Your go-to words.\nOne button away.", "常用的表达，\n一个按钮就好。")
        case .placement: return tr("バーの居場所は、\nあなたが決める。", "A small companion.\nIn the right place.", "小小工具栏，\n放在刚好的位置。")
        case .reply: return tr("コピーしたら、\n返信の準備完了。", "Copy the message.\nFind your words.", "复制对方的话，\n轻松开始回复。")
        }
    }

    var detail: String {
        switch self {
        case .buttons: return tr("よく使う指示をボタンとして保存。文章を選ぶか入力欄をクリックし、バーのボタンで書き換えられます。", "Save your favorite instructions as buttons. Select text or click a draft, then choose a button on the bar to rewrite it.", "将常用指令保存为按钮。选中文字或点击草稿输入框，再用工具栏上的按钮改写。")
        case .placement: return tr("バーをドラッグすると画面が暗くなり、白い枠が現れます。好きな枠の近くで離すと、その場所に収まります。", "Drag the bar to reveal four white drop zones on a dimmed screen. Release near one to snap the bar into place.", "拖动工具栏，屏幕会变暗并显示四个白色区域。在任一区域附近松开，工具栏就会贴靠到位。")
        case .reply: return tr("相手のメッセージをコピーし、返信欄をクリック。バーの「返信」から、伝えたいことを添えられます。", "Copy a message, click its reply field, then choose Reply on the bar. Add what you'd like to say.", "复制对方的消息，点击回复输入框，再选择工具栏上的「回复」，补充你想表达的内容。")
        }
    }

    var tip: String {
        switch self {
        case .buttons: return tr("「ボタン」で追加・編集・並べ替えができます。", "Add, edit, and reorder your instructions in Buttons.", "在「按钮」中添加、编辑和排列常用指令。")
        case .placement: return tr("近くの枠にドロップすると、その場所に収まります。", "Drop near a highlighted slot to snap the bar into place.", "在高亮区域附近松开，工具栏就会贴靠到位。")
        case .reply: return tr("コピーした内容は、返信を選んでから表示されます。", "The copied message appears only after you choose Reply.", "选择「回复」后，才会显示复制的消息内容。")
        }
    }
}
