import from "@jac/mobui" { StyleSheet }

obj Colors {
    has ink: str = "#1c2333",
        muted: str = "#6b7280",
        paper: str = "#f4f6fb",
        card: str = "#ffffff",
        line: str = "#e3e7f0",
        accent: str = "#2f4bd8";
}

glob:pub C = Colors(),
     S = StyleSheet.create(
         {
             "screen": {"flex": 1, "backgroundColor": C.paper},
             "page": {
                 "width": "100%",
                 "maxWidth": 1120,
                 "alignSelf": "center",
                 "padding": 24,
                 "gap": 28
             },
             "header": {
                 "flexDirection": "row",
                 "justifyContent": "space-between",
                 "alignItems": "center",
                 "paddingVertical": 12
             },
             "brand": {
                 "fontSize": 25,
                 "fontWeight": "800",
                 "color": C.ink,
                 "letterSpacing": -1
             },
             "eyebrow": {
                 "fontSize": 11,
                 "fontWeight": "700",
                 "letterSpacing": 2,
                 "color": C.accent
             },
             "title": {
                 "fontSize": 42,
                 "fontWeight": "700",
                 "letterSpacing": -2,
                 "color": C.ink
             },
             "subtitle": {"fontSize": 16, "lineHeight": 25, "color": C.muted},
             "row": {
                 "flexDirection": "row",
                 "gap": 12,
                 "alignItems": "center",
                 "flexWrap": "wrap"
             },
             "between": {
                 "flexDirection": "row",
                 "justifyContent": "space-between",
                 "alignItems": "center",
                 "gap": 12
             },
             "stack": {"gap": 16},
             "card": {
                 "backgroundColor": C.card,
                 "borderWidth": 1,
                 "borderColor": C.line,
                 "borderRadius": 18,
                 "padding": 22,
                 "gap": 16
             },
             "input": {
                 "borderWidth": 1,
                 "borderColor": C.line,
                 "borderRadius": 10,
                 "padding": 12,
                 "fontSize": 15,
                 "color": C.ink,
                 "backgroundColor": "#fff"
             },
             "composer": {"minHeight": 90, "textAlignVertical": "top"},
             "button": {
                 "backgroundColor": C.accent,
                 "paddingHorizontal": 18,
                 "paddingVertical": 11,
                 "borderRadius": 10,
                 "alignItems": "center"
             },
             "buttonText": {"color": "#fff", "fontWeight": "700", "fontSize": 14},
             "quiet": {"backgroundColor": "#e8ecfb"},
             "quietText": {"color": C.accent},
             "body": {"fontSize": 16, "lineHeight": 25, "color": C.ink},
             "small": {"fontSize": 12, "color": C.muted, "lineHeight": 19},
             "name": {"fontSize": 14, "fontWeight": "700", "color": C.ink},
             "avatar": {
                 "width": 42,
                 "height": 42,
                 "borderRadius": 21,
                 "backgroundColor": "#e8ecfb",
                 "justifyContent": "center",
                 "alignItems": "center"
             },
             "score": {
                 "fontSize": 56,
                 "fontWeight": "700",
                 "color": C.accent,
                 "letterSpacing": -3
             },
             "error": {
                 "padding": 14,
                 "borderRadius": 10,
                 "backgroundColor": "#fbe9e2",
                 "color": "#8c3524",
                 "fontSize": 14
             },
             "tabs": {
                 "flexDirection": "row",
                 "gap": 8,
                 "backgroundColor": "#e8ecfb",
                 "padding": 4,
                 "borderRadius": 12
             },
             "tab": {
                 "flex": 1,
                 "paddingVertical": 10,
                 "borderRadius": 9,
                 "alignItems": "center"
             },
             "tabOn": {"backgroundColor": "#ffffff"},
             "chip": {
                 "paddingHorizontal": 8,
                 "paddingVertical": 3,
                 "borderRadius": 999
             },
             "chipText": {"color": "#fff", "fontSize": 11, "fontWeight": "700"},
             "check": {
                 "width": 26,
                 "height": 26,
                 "borderRadius": 13,
                 "borderWidth": 2,
                 "borderColor": C.accent,
                 "alignItems": "center",
                 "justifyContent": "center"
             },
             "checkOn": {"backgroundColor": C.accent},
             "stat": {
                 "flex": 1,
                 "minWidth": 70,
                 "backgroundColor": C.card,
                 "borderWidth": 1,
                 "borderColor": C.line,
                 "borderRadius": 14,
                 "padding": 14,
                 "gap": 2
             },
             "statNum": {"fontSize": 22, "fontWeight": "800", "color": C.ink},
             "danger": {"color": "#c92a2a", "fontWeight": "700", "fontSize": 12},
             "dot": {"width": 14, "height": 14, "borderRadius": 7},
             "footer": {
                 "paddingVertical": 20,
                 "borderTopWidth": 1,
                 "borderTopColor": C.line
             },

         }
     );
