import type { Locale } from "./config";

type CommonCopy = {
  nav: {
    features: string;
    docs: string;
    support: string;
    privacy: string;
    download: string;
    downloadAria: string;
    homeAria: string;
    siteAria: string;
  };
  footer: {
    tagline: string;
    aria: string;
    home: string;
  };
  installCommand: {
    copy: string;
    copyAria: string;
    copied: string;
    copiedAria: string;
    pressCommandC: string;
    selectedAria: string;
  };
  shortcutKeys: {
    command: string;
    control: string;
    option: string;
    shift: string;
    escape: string;
    click: string;
  };
};

const common: Record<Locale, CommonCopy> = {
  en: {
    nav: {
      features: "Features",
      docs: "Docs",
      support: "Support",
      privacy: "Privacy",
      download: "Download",
      downloadAria: "Download Luxel on the Mac App Store",
      homeAria: "Luxel home",
      siteAria: "Site navigation"
    },
    footer: {
      tagline: "· Screen recording for Mac",
      aria: "Footer",
      home: "Home"
    },
    installCommand: {
      copy: "Copy",
      copyAria: "Copy install command",
      copied: "Copied",
      copiedAria: "Install command copied",
      pressCommandC: "Press ⌘C",
      selectedAria: "Install command selected; press Command-C to copy"
    },
    shortcutKeys: {
      command: "Command",
      control: "Control",
      option: "Option",
      shift: "Shift",
      escape: "Escape",
      click: "Click"
    }
  },
  de: {
    nav: {
      features: "Funktionen",
      docs: "Dokumentation",
      support: "Support",
      privacy: "Datenschutz",
      download: "Laden",
      downloadAria: "Luxel im Mac App Store laden",
      homeAria: "Luxel-Startseite",
      siteAria: "Seitennavigation"
    },
    footer: {
      tagline: "· Bildschirmaufnahme für den Mac",
      aria: "Fußzeile",
      home: "Startseite"
    },
    installCommand: {
      copy: "Kopieren",
      copyAria: "Installationsbefehl kopieren",
      copied: "Kopiert",
      copiedAria: "Installationsbefehl kopiert",
      pressCommandC: "⌘C drücken",
      selectedAria: "Installationsbefehl ausgewählt; zum Kopieren Command-C drücken"
    },
    shortcutKeys: {
      command: "Befehl",
      control: "Control",
      option: "Option",
      shift: "Umschalttaste",
      escape: "Escape",
      click: "Klick"
    }
  },
  es: {
    nav: {
      features: "Funciones",
      docs: "Documentación",
      support: "Soporte",
      privacy: "Privacidad",
      download: "Descargar",
      downloadAria: "Descargar Luxel en el Mac App Store",
      homeAria: "Inicio de Luxel",
      siteAria: "Navegación del sitio"
    },
    footer: {
      tagline: "· Grabación de pantalla para Mac",
      aria: "Pie de página",
      home: "Inicio"
    },
    installCommand: {
      copy: "Copiar",
      copyAria: "Copiar comando de instalación",
      copied: "Copiado",
      copiedAria: "Comando de instalación copiado",
      pressCommandC: "Pulsa ⌘C",
      selectedAria: "Comando de instalación seleccionado; pulsa Comando-C para copiar"
    },
    shortcutKeys: {
      command: "Comando",
      control: "Control",
      option: "Opción",
      shift: "Mayúsculas",
      escape: "Escape",
      click: "Clic"
    }
  },
  fr: {
    nav: {
      features: "Fonctionnalités",
      docs: "Documentation",
      support: "Assistance",
      privacy: "Confidentialité",
      download: "Télécharger",
      downloadAria: "Télécharger Luxel sur le Mac App Store",
      homeAria: "Accueil de Luxel",
      siteAria: "Navigation du site"
    },
    footer: {
      tagline: "· Enregistrement d’écran pour Mac",
      aria: "Pied de page",
      home: "Accueil"
    },
    installCommand: {
      copy: "Copier",
      copyAria: "Copier la commande d’installation",
      copied: "Copié",
      copiedAria: "Commande d’installation copiée",
      pressCommandC: "Appuyez sur ⌘C",
      selectedAria: "Commande d’installation sélectionnée ; appuyez sur Commande-C pour copier"
    },
    shortcutKeys: {
      command: "Commande",
      control: "Contrôle",
      option: "Option",
      shift: "Majuscule",
      escape: "Échap",
      click: "Clic"
    }
  },
  it: {
    nav: {
      features: "Funzionalità",
      docs: "Documentazione",
      support: "Assistenza",
      privacy: "Privacy",
      download: "Scarica",
      downloadAria: "Scarica Luxel dal Mac App Store",
      homeAria: "Home di Luxel",
      siteAria: "Navigazione del sito"
    },
    footer: {
      tagline: "· Registrazione schermo per Mac",
      aria: "Piè di pagina",
      home: "Home"
    },
    installCommand: {
      copy: "Copia",
      copyAria: "Copia il comando di installazione",
      copied: "Copiato",
      copiedAria: "Comando di installazione copiato",
      pressCommandC: "Premi ⌘C",
      selectedAria: "Comando di installazione selezionato; premi Comando-C per copiarlo"
    },
    shortcutKeys: {
      command: "Comando",
      control: "Control",
      option: "Opzione",
      shift: "Maiuscole",
      escape: "Esc",
      click: "Clic"
    }
  },
  ja: {
    nav: {
      features: "機能",
      docs: "ドキュメント",
      support: "サポート",
      privacy: "プライバシー",
      download: "ダウンロード",
      downloadAria: "Mac App StoreでLuxelをダウンロード",
      homeAria: "Luxelホーム",
      siteAria: "サイトナビゲーション"
    },
    footer: {
      tagline: "· Mac用画面収録",
      aria: "フッター",
      home: "ホーム"
    },
    installCommand: {
      copy: "コピー",
      copyAria: "インストールコマンドをコピー",
      copied: "コピー済み",
      copiedAria: "インストールコマンドをコピーしました",
      pressCommandC: "⌘Cを押す",
      selectedAria: "インストールコマンドを選択しました。Command-Cでコピーしてください"
    },
    shortcutKeys: {
      command: "Command",
      control: "Control",
      option: "Option",
      shift: "Shift",
      escape: "Escape",
      click: "クリック"
    }
  },
  ko: {
    nav: {
      features: "기능",
      docs: "문서",
      support: "지원",
      privacy: "개인정보 보호",
      download: "다운로드",
      downloadAria: "Mac App Store에서 Luxel 다운로드",
      homeAria: "Luxel 홈",
      siteAria: "사이트 탐색"
    },
    footer: {
      tagline: "· Mac용 화면 녹화",
      aria: "바닥글",
      home: "홈"
    },
    installCommand: {
      copy: "복사",
      copyAria: "설치 명령 복사",
      copied: "복사됨",
      copiedAria: "설치 명령이 복사되었습니다",
      pressCommandC: "⌘C 누르기",
      selectedAria: "설치 명령이 선택되었습니다. Command-C를 눌러 복사하세요"
    },
    shortcutKeys: {
      command: "Command",
      control: "Control",
      option: "Option",
      shift: "Shift",
      escape: "Escape",
      click: "클릭"
    }
  },
  vi: {
    nav: {
      features: "Tính năng",
      docs: "Tài liệu",
      support: "Hỗ trợ",
      privacy: "Quyền riêng tư",
      download: "Tải xuống",
      downloadAria: "Tải Luxel trên Mac App Store",
      homeAria: "Trang chủ Luxel",
      siteAria: "Điều hướng trang web"
    },
    footer: {
      tagline: "· Ghi màn hình cho Mac",
      aria: "Chân trang",
      home: "Trang chủ"
    },
    installCommand: {
      copy: "Sao chép",
      copyAria: "Sao chép lệnh cài đặt",
      copied: "Đã sao chép",
      copiedAria: "Đã sao chép lệnh cài đặt",
      pressCommandC: "Nhấn ⌘C",
      selectedAria: "Đã chọn lệnh cài đặt; nhấn Command-C để sao chép"
    },
    shortcutKeys: {
      command: "Command",
      control: "Control",
      option: "Option",
      shift: "Shift",
      escape: "Escape",
      click: "Nhấp"
    }
  },
  "zh-Hans": {
    nav: {
      features: "功能",
      docs: "文档",
      support: "支持",
      privacy: "隐私",
      download: "下载",
      downloadAria: "在 Mac App Store 下载 Luxel",
      homeAria: "Luxel 首页",
      siteAria: "网站导航"
    },
    footer: {
      tagline: "· Mac 屏幕录制",
      aria: "页脚",
      home: "首页"
    },
    installCommand: {
      copy: "复制",
      copyAria: "复制安装命令",
      copied: "已复制",
      copiedAria: "已复制安装命令",
      pressCommandC: "按 ⌘C",
      selectedAria: "已选择安装命令；按 Command-C 复制"
    },
    shortcutKeys: {
      command: "Command",
      control: "Control",
      option: "Option",
      shift: "Shift",
      escape: "Escape",
      click: "点击"
    }
  },
  "pt-BR": {
    nav: {
      features: "Recursos",
      docs: "Documentação",
      support: "Suporte",
      privacy: "Privacidade",
      download: "Baixar",
      downloadAria: "Baixar o Luxel na Mac App Store",
      homeAria: "Início do Luxel",
      siteAria: "Navegação do site"
    },
    footer: {
      tagline: "· Gravação de tela para Mac",
      aria: "Rodapé",
      home: "Início"
    },
    installCommand: {
      copy: "Copiar",
      copyAria: "Copiar comando de instalação",
      copied: "Copiado",
      copiedAria: "Comando de instalação copiado",
      pressCommandC: "Pressione ⌘C",
      selectedAria: "Comando de instalação selecionado; pressione Command-C para copiar"
    },
    shortcutKeys: {
      command: "Command",
      control: "Control",
      option: "Option",
      shift: "Shift",
      escape: "Escape",
      click: "Clique"
    }
  },
  "pt-PT": {
    nav: {
      features: "Funcionalidades",
      docs: "Documentação",
      support: "Suporte",
      privacy: "Privacidade",
      download: "Descarregar",
      downloadAria: "Descarregar o Luxel na Mac App Store",
      homeAria: "Início do Luxel",
      siteAria: "Navegação do site"
    },
    footer: {
      tagline: "· Gravação de ecrã para Mac",
      aria: "Rodapé",
      home: "Início"
    },
    installCommand: {
      copy: "Copiar",
      copyAria: "Copiar comando de instalação",
      copied: "Copiado",
      copiedAria: "Comando de instalação copiado",
      pressCommandC: "Prima ⌘C",
      selectedAria: "Comando de instalação selecionado; prima Command-C para copiar"
    },
    shortcutKeys: {
      command: "Command",
      control: "Control",
      option: "Option",
      shift: "Shift",
      escape: "Escape",
      click: "Clique"
    }
  }
};

export function commonCopy(locale: Locale): CommonCopy {
  return common[locale];
}
