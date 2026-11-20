import Foundation

/// 界面语言（FishPocket/用户原要求）：简体/繁體/English/Español/日本語/한국어。
/// 核心界面字符串表；换语言立即生效（读 store.language，视图跟着重绘）。
/// 没译到的键回落简体中文。
enum L10n {
    static let languages: [(code: String, name: String)] = [
        ("zh-Hans", "简体中文"),
        ("zh-Hant", "繁體中文"),
        ("en", "English"),
        ("es", "Español"),
        ("ja", "日本語"),
        ("ko", "한국어"),
    ]

    static func t(_ key: String, lang: String) -> String {
        table[lang]?[key] ?? table["zh-Hans"]?[key] ?? key
    }

    private static let table: [String: [String: String]] = [
        "zh-Hans": [
            "tab_chat": "聊天", "tab_skills": "技能", "tab_browser": "浏览器", "tab_settings": "设置",
            "tab_agents": "智能体", "tab_apps": "我的应用", "tab_explore": "探索",
            "cloud_computer": "云电脑", "explore": "探索",
            "nav_chat": "聊天", "direct_chat": "直接聊", "direct_hint": "不用建智能体，点开就能聊",
            "new_chat": "新建", "search": "搜索", "settings": "设置",
            "agents": "智能体", "providers": "供应商与模型", "skills": "技能", "plugins": "插件",
            "dns": "DNS", "connectors": "连接工具", "server_browser": "服务器浏览器", "log": "日志",
            "schedules": "定时任务", "mini_apps": "小工具", "language": "语言",
            "usage": "用量统计", "update": "检查更新", "device_caps": "本机能力",
            "cancel": "取消", "save": "保存", "close": "关闭", "delete": "删除",
            "send_placeholder": "发消息", "thinking": "思考中…",
            "empty_title": "想聊就聊", "empty_hint": "点下面直接开聊，第一次会让你选个免费源填 Key。\n想组智能体团队，再点新建。",
            "no_agents": "还没有智能体。在聊天列表右上角新建里建。",
        ],
        "zh-Hant": [
            "tab_chat": "聊天", "tab_skills": "技能", "tab_browser": "瀏覽器", "tab_settings": "設定",
            "nav_chat": "聊天", "direct_chat": "直接聊", "direct_hint": "不用建智能體，點開就能聊",
            "new_chat": "新建", "search": "搜尋", "settings": "設定",
            "agents": "智能體", "providers": "供應商與模型", "skills": "技能", "plugins": "外掛",
            "dns": "DNS", "connectors": "連接工具", "server_browser": "伺服器瀏覽器", "log": "日誌",
            "schedules": "定時任務", "mini_apps": "小工具", "language": "語言",
            "usage": "用量統計", "update": "檢查更新", "device_caps": "本機能力",
            "cancel": "取消", "save": "儲存", "close": "關閉", "delete": "刪除",
            "send_placeholder": "發訊息", "thinking": "思考中…",
            "empty_title": "想聊就聊", "empty_hint": "點下面直接開聊，第一次會讓你選個免費來源填 Key。\n想組智能體團隊，再點新建。",
            "no_agents": "還沒有智能體。在聊天列表右上角新建裡建。",
        ],
        "en": [
            "tab_chat": "Chat", "tab_skills": "Skills", "tab_browser": "Browser", "tab_settings": "Settings",
            "tab_agents": "Agents", "tab_apps": "My Apps", "tab_explore": "Explore",
            "cloud_computer": "Cloud Computer", "explore": "Explore",
            "nav_chat": "Chat", "direct_chat": "Chat now", "direct_hint": "No setup needed, just start chatting",
            "new_chat": "New", "search": "Search", "settings": "Settings",
            "agents": "Agents", "providers": "Providers & Models", "skills": "Skills", "plugins": "Plugins",
            "dns": "DNS", "connectors": "Connectors", "server_browser": "Server Browser", "log": "Logs",
            "schedules": "Schedules", "mini_apps": "Mini Apps", "language": "Language",
            "usage": "Usage", "update": "Check for Updates", "device_caps": "Device Capabilities",
            "cancel": "Cancel", "save": "Save", "close": "Close", "delete": "Delete",
            "send_placeholder": "Message", "thinking": "Thinking…",
            "empty_title": "Just start chatting", "empty_hint": "Tap below to chat right away. First time, pick a free provider and enter its key.\nTo build an agent team, tap New.",
            "no_agents": "No agents yet. Create one from New at the top right of the chat list.",
        ],
        "es": [
            "tab_chat": "Chat", "tab_skills": "Skills", "tab_browser": "Navegador", "tab_settings": "Ajustes",
            "nav_chat": "Chat", "direct_chat": "Chatear", "direct_hint": "Sin configurar nada, empieza a chatear",
            "new_chat": "Nuevo", "search": "Buscar", "settings": "Ajustes",
            "agents": "Agentes", "providers": "Proveedores y modelos", "skills": "Skills", "plugins": "Plugins",
            "dns": "DNS", "connectors": "Conectores", "server_browser": "Navegador del servidor", "log": "Registro",
            "schedules": "Tareas programadas", "mini_apps": "Mini apps", "language": "Idioma",
            "usage": "Uso", "update": "Buscar actualizaciones", "device_caps": "Capacidades del dispositivo",
            "cancel": "Cancelar", "save": "Guardar", "close": "Cerrar", "delete": "Eliminar",
            "send_placeholder": "Mensaje", "thinking": "Pensando…",
            "empty_title": "Empieza a chatear", "empty_hint": "Toca abajo para chatear. La primera vez elige un proveedor gratuito y pon su clave.\nPara crear un equipo de agentes, toca Nuevo.",
            "no_agents": "Aún no hay agentes. Crea uno desde Nuevo, arriba a la derecha de la lista.",
        ],
        "ja": [
            "tab_chat": "チャット", "tab_skills": "スキル", "tab_browser": "ブラウザ", "tab_settings": "設定",
            "nav_chat": "チャット", "direct_chat": "すぐ話す", "direct_hint": "設定なしでそのまま話せる",
            "new_chat": "新規", "search": "検索", "settings": "設定",
            "agents": "エージェント", "providers": "プロバイダとモデル", "skills": "スキル", "plugins": "プラグイン",
            "dns": "DNS", "connectors": "コネクタ", "server_browser": "サーバーブラウザ", "log": "ログ",
            "schedules": "スケジュール", "mini_apps": "ミニアプリ", "language": "言語",
            "usage": "使用量", "update": "更新を確認", "device_caps": "デバイス機能",
            "cancel": "キャンセル", "save": "保存", "close": "閉じる", "delete": "削除",
            "send_placeholder": "メッセージ", "thinking": "考え中…",
            "empty_title": "すぐ話そう", "empty_hint": "下をタップしてすぐ話せます。最初は無料プロバイダを選んでキーを入力してください。\nエージェントチームを作るには「新規」をタップ。",
            "no_agents": "エージェントはまだありません。チャット一覧右上の「新規」から作ってください。",
        ],
        "ko": [
            "tab_chat": "채팅", "tab_skills": "스킬", "tab_browser": "브라우저", "tab_settings": "설정",
            "nav_chat": "채팅", "direct_chat": "바로 채팅", "direct_hint": "설정 없이 바로 채팅",
            "new_chat": "새로 만들기", "search": "검색", "settings": "설정",
            "agents": "에이전트", "providers": "공급자 및 모델", "skills": "스킬", "plugins": "플러그인",
            "dns": "DNS", "connectors": "커넥터", "server_browser": "서버 브라우저", "log": "로그",
            "schedules": "예약 작업", "mini_apps": "미니 앱", "language": "언어",
            "usage": "사용량", "update": "업데이트 확인", "device_caps": "기기 기능",
            "cancel": "취소", "save": "저장", "close": "닫기", "delete": "삭제",
            "send_placeholder": "메시지", "thinking": "생각 중…",
            "empty_title": "바로 채팅하기", "empty_hint": "아래를 눌러 바로 채팅하세요. 처음에는 무료 공급자를 선택하고 키를 입력하세요.\n에이전트 팀을 만들려면 새로 만들기를 누르세요.",
            "no_agents": "에이전트가 아직 없습니다. 채팅 목록 오른쪽 위의 새로 만들기에서 만드세요.",
        ],
    ]
}
