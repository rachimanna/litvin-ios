// @name        Litvin Tools
// @description Команды .shrug .time .flip .mock и автозамена :) → 😊
// @author      Litvin
// @version     1.0

litvin.command("shrug", "Пожать плечами", function (args) {
    return (args ? args + " " : "") + "¯\\_(ツ)_/¯";
});

litvin.command("time", "Текущее время", function () {
    var d = new Date();
    function two(n) { return (n < 10 ? "0" : "") + n; }
    return "🕒 " + two(d.getHours()) + ":" + two(d.getMinutes());
});

litvin.command("flip", "Перевернуть текст", function (args) {
    return args.split("").reverse().join("");
});

litvin.command("mock", "ТаКоЙ ТеКсТ", function (args) {
    var out = "";
    for (var i = 0; i < args.length; i++) {
        out += i % 2 ? args[i].toLowerCase() : args[i].toUpperCase();
    }
    return out;
});

litvin.onOutgoingMessage(function (text) {
    return text.replace(/:\)/g, "😊").replace(/:\(/g, "😔").replace(/<3/g, "❤️");
});
