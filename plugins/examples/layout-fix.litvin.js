// @name        Раскладка
// @description .ru ghbdtn → привет: исправляет текст, набранный не в той раскладке. .en руддщ → hello
// @author      Litvin
// @version     1.0

var en = "`qwertyuiop[]asdfghjkl;'zxcvbnm,./~QWERTYUIOP{}ASDFGHJKL:\"ZXCVBNM<>?";
var ru = "ёйцукенгшщзхъфывапролджэячсмитьбю.ЁЙЦУКЕНГШЩЗХЪФЫВАПРОЛДЖЭЯЧСМИТЬБЮ,";

function convert(text, from, to) {
    var out = "";
    for (var i = 0; i < text.length; i++) {
        var index = from.indexOf(text[i]);
        out += index >= 0 ? to[index] : text[i];
    }
    return out;
}

litvin.command("ru", "Английская раскладка → русская", function (args) {
    return convert(args, en, ru);
});

litvin.command("en", "Русская раскладка → английская", function (args) {
    return convert(args, ru, en);
});
