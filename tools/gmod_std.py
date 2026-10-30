import re
import sys
from pathlib import Path

IDENT = r"[A-Za-z_][A-Za-z0-9_]*"


def scan(src: Path) -> tuple[set[str], dict[str, set[str]]]:
    plain: set[str] = set()
    libs: dict[str, set[str]] = {}
    classes: set[str] = set()
    for f in sorted(src.glob("*.lua")):
        lines = f.read_text().splitlines()
        local_tables = {m[1] for line in lines if (m := re.match(rf"^local ({IDENT}) = ", line))}
        for i, line in enumerate(lines):
            prev = lines[i - 1] if i else ""
            if m := re.match(rf"^({IDENT}) = \{{\}}", line):
                if prev.startswith("---@class"):
                    classes.add(m[1])
                else:
                    libs.setdefault(m[1], set())
            elif m := re.match(rf"^function _G\.({IDENT})\(", line):
                plain.add(m[1])
            elif m := re.match(rf"^function ({IDENT})\.({IDENT})\(", line):
                if m[1] not in classes and m[1] not in local_tables:
                    libs.setdefault(m[1], set()).add(m[2])
            elif m := re.match(rf"^({IDENT})\.({IDENT}) = ", line):
                if m[1] in libs:
                    libs[m[1]].add(m[2])
            elif m := re.match(rf"^function ({IDENT})\(", line):
                plain.add(m[1])
            elif m := re.match(rf"^({IDENT}) = ", line):
                plain.add(m[1])
    for name in classes:
        libs.pop(name, None)
    return plain - set(libs), libs


def render(plain: set[str], libs: dict[str, set[str]]) -> str:
    out = ["return {", "\tread_globals = {"]
    out += [f'\t\t"{name}",' for name in sorted(plain)]
    for name in sorted(libs):
        if libs[name]:
            fields = ", ".join(f'"{f}"' for f in sorted(libs[name]))
            out.append(f"\t\t{name} = {{ fields = {{ {fields} }} }},")
        else:
            out.append(f'\t\t"{name}",')
    out += ["\t},", "}", ""]
    return "\n".join(out)


def main() -> None:
    src, dest = Path(sys.argv[1]), Path(sys.argv[2])
    plain, libs = scan(src)
    dest.write_text(render(plain, libs))
    print(f"{len(plain)} globals, {len(libs)} libraries, {sum(map(len, libs.values()))} library functions")


main()
