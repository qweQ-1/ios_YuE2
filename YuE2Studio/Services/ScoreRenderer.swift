import Foundation

/// 把 ABC 乐谱渲染成离线 HTML（配合 bundle 内 abcjs-basic-min.js）。
public enum ScoreRenderer {
    /// abcjs 渲染器文件名（作为资源打进 bundle）。
    public static let jsFileName = "abcjs-basic-min.js"

    /// 生成完整 HTML：加载 abcjs → 在 #paper 渲染传入 ABC。无网络依赖。
    public static func html(forScore abc: String, staffWidth: CGFloat = 360) -> String {
        let literal = jsStringLiteral(abc)
        return """
        <!DOCTYPE html>
        <html lang="zh">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          html, body { margin: 0; padding: 8px; background: #101018; color: #eee; }
          #paper { width: 100%; overflow-x: auto; }
          #paper svg { max-width: 100%; height: auto; }
        </style>
        <script src="\(jsFileName)"></script>
        </head>
        <body>
        <div id="paper"></div>
        <script>
          window.addEventListener('load', function () {
            try {
              ABCJS.renderAbc('paper', \(literal), {
                responsive: 'resize',
                staffwidth: \(Int(staffWidth)),
                add_classes: true,
                format: {
                  titlebox: false,
                  gchordfont: "Helvetica",
                  annotationfont: "Helvetica",
                  infofont: "Helvetica",
                  vocalfont: "Helvetica",
                  composerfont: "Helvetica",
                  stretchlast: 0.6
                }
              });
            } catch (e) {
              document.getElementById('paper').textContent = '乐谱渲染失败：' + e;
            }
          });
        </script>
        </body>
        </html>
        """
    }

    /// 把任意文本转成安全 JS 字符串字面量（含反转义尖括号防 </script> 截断）。
    static func jsStringLiteral(_ text: String) -> String {
        var out = "\""
        for ch in text {
            switch ch {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "<": out += "\\u003C"
            case ">": out += "\\u003E"
            case "&": out += "\\u0026"
            case "\u{2028}": out += "\\u2028"
            case "\u{2029}": out += "\\u2029"
            default: out.append(ch)
            }
        }
        out += "\""
        return out
    }
}
