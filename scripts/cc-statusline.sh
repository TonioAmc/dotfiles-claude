#!/usr/bin/env bash
# Claude Code statusline: rama git + cwd + modelo
# Recibe JSON por stdin; imprime una sola línea a stdout (sin newline).

input=$(cat)

# '|' como delimitador (no-whitespace) para preservar campos vacíos.
# Con IFS=$'\t' + @tsv, bash colapsaba tabs consecutivos cuando
# context_window.used_percentage es null, desplazando todos los campos.
IFS='|' read -r cwd model effort ctx_tok ctx_size ctx_pct rl rl_resets <<<"$(
    echo "$input" | jq -r '[
        .workspace.current_dir // .cwd // "",
        .model.display_name // "",
        .effort.level // "",
        .context_window.total_input_tokens,
        .context_window.context_window_size,
        .context_window.used_percentage,
        .rate_limits.five_hour.used_percentage,
        .rate_limits.five_hour.resets_at
    ] | join("|")'
)"

# Path corto: ~ si es home, basename si está dentro de un proyecto.
# Si es worktree, separar nombre del repo principal y sufijo del worktree.
short_path="${cwd/#$HOME/~}"
is_worktree=""
if git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1; then
    common_dir=$(git -C "$cwd" rev-parse --git-common-dir 2>/dev/null)
    case "$common_dir" in
        /*) ;;
        *) common_dir="$cwd/$common_dir" ;;
    esac
    main_repo_path=$(cd "$(dirname "$common_dir")" 2>/dev/null && pwd)
    main_repo_name=$(basename "$main_repo_path")
    current_top=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)
    rel=$(git -C "$cwd" rev-parse --show-prefix 2>/dev/null)

    # Worktree: el toplevel actual difiere del repo principal. Solo marcamos un
    # glifo ⎇ junto al proyecto; el nombre del directorio worktree es redundante
    # con la rama (ambos describen la feature), así que ya no lo mostramos.
    if [ -n "$current_top" ] && [ "$current_top" != "$main_repo_path" ]; then
        is_worktree=1
    fi

    proj="$main_repo_name"
    [ -n "$rel" ] && short_path="$proj/${rel%/}" || short_path="$proj"
fi

# Rama git + dirty flag
branch=""
if git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1; then
    branch=$(git -C "$cwd" branch --show-current 2>/dev/null)
    [ -z "$branch" ] && branch=$(git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
    if [ -n "$(git -C "$cwd" status --porcelain 2>/dev/null | head -1)" ]; then
        branch="${branch}*"
    fi
fi

# Dev server de ESTE worktree: escanea sockets LISTEN y se queda con los puertos
# cuyo proceso tiene su cwd dentro del toplevel del worktree actual. Así cada
# consola muestra SU propio puerto (distinto por rama/worktree), sin configuración:
# refleja el runserver/vite real que esté corriendo. Procesos de otros usuarios
# (root, etc.) → readlink de su /proc/<pid>/cwd falla → se descartan solos.
server_label=""
# Solo dentro de un repo/worktree git: si $cwd no es git, current_top queda vacío
# y NO detectamos (si no, en $HOME matchearíamos los servers de TODOS los proyectos).
detect_root="${current_top}"
if [ -n "$detect_root" ] && command -v ss >/dev/null 2>&1; then
    srv_ports=()
    declare -A srv_seen=()
    while read -r ss_line; do
        [[ "$ss_line" == *pid=* ]] || continue
        sp_pid="${ss_line##*pid=}"; sp_pid="${sp_pid%%,*}"
        [[ "$sp_pid" =~ ^[0-9]+$ ]] || continue
        sp_cwd=$(readlink "/proc/$sp_pid/cwd" 2>/dev/null) || continue
        case "$sp_cwd" in
            "$detect_root"|"$detect_root"/*) ;;
            *) continue ;;
        esac
        # Solo dev servers reales: filtra por línea de comando para no colar daemons
        # que casualmente tienen su cwd en el worktree (adb, language servers, etc.).
        # Agregar patrones acá si usás otro framework.
        sp_cmd=$(tr '\0' ' ' < "/proc/$sp_pid/cmdline" 2>/dev/null)
        case "$sp_cmd" in
            *runserver*|*manage.py*|*vite*|*"next dev"*|*next-server*|*webpack*|\
            *uvicorn*|*gunicorn*|*hypercorn*|*daphne*|*"flask run"*|*"http.server"*|\
            *"artisan serve"*|*"rails s"*|*puma*|*nuxt*|*astro*|*"npm run dev"*|\
            *"pnpm dev"*|*"yarn dev"*|*"bun run dev"*) ;;
            *) continue ;;
        esac
        # 4to campo de `ss` = dirección local (127.0.0.1:8000, *:5173, [::1]:8000)
        sp_addr=$(awk '{print $4}' <<<"$ss_line")
        sp_port="${sp_addr##*:}"
        [[ "$sp_port" =~ ^[0-9]+$ ]] || continue
        [ -n "${srv_seen[$sp_port]}" ] && continue   # dedup IPv4/IPv6 mismo puerto
        srv_seen[$sp_port]=1
        srv_ports+=("$sp_port")
    done < <(ss -tlnpH 2>/dev/null)
    if [ ${#srv_ports[@]} -gt 0 ]; then
        IFS=$'\n' srv_ports=($(sort -n <<<"${srv_ports[*]}")); unset IFS
        # Hyperlink OSC 8: muestra ":PORT" corto, pero el click (ctrl+shift+click en
        # kitty) abre la URL completa http://localhost:PORT. Así el statusline no se
        # llena con la URL larga. visible_len() ignora estas secuencias al medir.
        server_label="🌐"
        for sp in "${srv_ports[@]}"; do
            link=$(printf '\e]8;;http://localhost:%s\e\\:%s\e]8;;\e\\' "$sp" "$sp")
            server_label="${server_label} ${link}"
        done
    fi
fi

# ANSI colors (256-color)
C_BRANCH=$'\e[38;5;114m'   # verde suave
C_OK=$'\e[38;5;114m'       # verde "todo bien"
C_DIRTY=$'\e[38;5;215m'    # naranja si dirty
C_PATH=$'\e[38;5;180m'     # beige
C_WT=$'\e[38;5;141m'       # violeta para worktree
C_MODEL=$'\e[38;5;245m'    # gris (fallback)
C_SEP=$'\e[38;5;96m'       # rosa apagado
C_EFFORT=$'\e[38;5;110m'   # azul pálido
C_WARN=$'\e[38;5;215m'     # naranja para alertas
C_CRIT=$'\e[38;5;203m'     # rojo para crítico
C_OPUS=$'\e[38;5;141m'     # violeta
C_SONNET=$'\e[38;5;75m'    # azul
C_HAIKU=$'\e[38;5;114m'    # verde
C_SERVER=$'\e[38;5;80m'    # cyan para la URL del dev server
RESET=$'\e[0m'

# Gradiente iridiscente: cada carácter del nombre recibe un color del espectro
fable_rainbow() {
    local text="$1"
    local colors=(
        $'\e[1;38;5;201m'
        $'\e[1;38;5;135m'
        $'\e[1;38;5;75m'
        $'\e[1;38;5;51m'
        $'\e[1;38;5;87m'
        $'\e[1;38;5;154m'
        $'\e[1;38;5;220m'
    )
    local len=${#text} result=""
    for (( i=0; i<len; i++ )); do
        result+="${colors[$((i % ${#colors[@]}))]}"
        result+="${text:$i:1}"
    done
    printf '%s%s' "$result" "$RESET"
}

# --- Helpers de ancho (definidos arriba: se usan para presupuestar la rama antes de
# --- construir la línea, no solo al final para decidir 1 vs 2 líneas).
sep="${C_SEP} │ ${RESET}"
SEP_VLEN=3                 # ancho visible de " │ "

# Une un array con el separador.
join_parts() {
    local -n arr=$1
    local result=""
    for p in "${arr[@]}"; do
        [ -n "$result" ] && result="${result}${sep}"
        result="${result}${p}"
    done
    printf '%s' "$result"
}

# Longitud visible (sin ANSI ni hyperlinks OSC 8) de un string coloreado.
visible_len() {
    # Quita hyperlinks OSC 8 (\e]8;;URL\e\\ … \e]8;;\e\\) y colores CSI (\e[…m)
    # para contar solo los caracteres realmente visibles en pantalla.
    echo -n "$1" | sed -E 's/\x1b\]8;;[^\x1b]*\x1b\\//g; s/\x1b\[[0-9;]*m//g' | wc -m
}

# Trunca un texto a `max` caracteres con elipsis en el MEDIO, preservando prefijo y
# sufijo. Para ramas tipo `fix/…-liquidaciones` esto conserva el tipo (fix/feat) y la
# parte distintiva del final, que es lo informativo. El `*` de dirty queda en el sufijo.
truncate_mid() {
    local s="$1" max="$2" n=${#1}
    [ "$n" -le "$max" ] && { printf '%s' "$s"; return; }
    [ "$max" -lt 3 ] && { printf '%s' "${s:0:max}"; return; }
    local keep=$(( max - 1 )) head tail   # 1 carácter para la elipsis …
    head=$(( (keep + 1) / 2 )); tail=$(( keep - head ))
    printf '%s…%s' "${s:0:head}" "${s: -tail}"
}

# Ancho de terminal — Claude Code no pasa COLUMNS y el statusline corre sin TTY.
# Se resuelve ACÁ (antes de armar la línea) porque el presupuesto de la rama lo necesita.
# Estrategia en cascada:
#   1) kitty vía remote control (cacheado 1s para no spamear cuando refresca seguido).
#   2) Subir el árbol de procesos hasta el proceso de Claude Code (que sí tiene el
#      pts de la terminal en sus fd) y leer el ancho con `stty size`. Universal:
#      funciona en konsole, kitty y cualquier emulador con TTY real.
#   3) Fallbacks COLUMNS / tput / 200.
cols=""
cache="/tmp/cc-statusline-cols-${KITTY_WINDOW_ID:-x}"
if [ -n "$KITTY_WINDOW_ID" ] && command -v kitten >/dev/null 2>&1; then
    if [ -f "$cache" ] && [ $(( $(date +%s) - $(stat -c %Y "$cache" 2>/dev/null || echo 0) )) -lt 1 ]; then
        cols=$(cat "$cache")
    else
        cols=$(kitten @ ls --match "id:${KITTY_WINDOW_ID}" 2>/dev/null \
               | jq -r '[.[]|.tabs[]|.windows[]|select(.id=='"$KITTY_WINDOW_ID"')|.columns][0] // empty')
        [ -n "$cols" ] && echo "$cols" > "$cache"
    fi
fi

# pts-walk: el statusline no tiene TTY, pero un ancestro (el proceso de Claude Code)
# sí tiene el pts en fd 0/1/2. Subimos por ppid leyendo /proc/<pid>/stat de forma
# robusta (el comm puede llevar espacios/paréntesis → cortamos hasta el último ')').
if [ -z "$cols" ]; then
    walk_pid=$$
    for _ in 1 2 3 4 5 6 7 8; do
        for fd in 0 1 2; do
            case "$(readlink "/proc/$walk_pid/fd/$fd" 2>/dev/null)" in
                /dev/pts/*)
                    sz=$(stty size <"/proc/$walk_pid/fd/$fd" 2>/dev/null) && cols=${sz#* }
                    ;;
            esac
            [ -n "$cols" ] && break
        done
        [ -n "$cols" ] && break
        pstat=$(cat "/proc/$walk_pid/stat" 2>/dev/null) || break
        rest=${pstat##*) }          # descarta pid y "(comm)"
        set -- $rest                # $1=state  $2=ppid
        walk_pid=$2
        { [ -z "$walk_pid" ] || [ "$walk_pid" -le 1 ]; } 2>/dev/null && break
    done
    [[ "$cols" =~ ^[0-9]+$ ]] || cols=""
fi

[ -z "$cols" ] && cols=${COLUMNS:-$(tput cols 2>/dev/null || echo 200)}

# --- Construir la línea 1 ---
# Primero los elementos que van DESPUÉS de la rama (proyecto/worktree, server, modelo):
# son los que el usuario quiere ver siempre. Medimos su ancho y le damos a la rama el
# espacio que sobra hasta `cols`; si no entra, la truncamos. Así un nombre de rama largo
# (p.ej. fix/tarjeta-boletas-cuenta-liquidaciones) nunca empuja el modelo/puertos fuera.
rest_parts=()
if [ -n "$is_worktree" ]; then
    rest_parts+=("${C_WT}⎇ ${RESET}${C_PATH}${short_path}${RESET}")
else
    rest_parts+=("${C_PATH}${short_path}${RESET}")
fi
if [ -n "$server_label" ]; then
    rest_parts+=("${C_SERVER}${server_label}${RESET}")
fi
if [ -n "$model" ]; then
    # Abreviar: quitar el paréntesis "(1M context)" y similares. La variante 1M es
    # la única que usás, así que ese sufijo no aporta y antes se truncaba.
    model_disp="${model%% (*}"
    model_lower=$(echo "$model" | tr '[:upper:]' '[:lower:]')
    case "$model_lower" in
        *fable*)  rest_parts+=("$(fable_rainbow "$model_disp")") ;;
        *opus*)   rest_parts+=("${C_OPUS}${model_disp}${RESET}") ;;
        *sonnet*) rest_parts+=("${C_SONNET}${model_disp}${RESET}") ;;
        *haiku*)  rest_parts+=("${C_HAIKU}${model_disp}${RESET}") ;;
        *)        rest_parts+=("${C_MODEL}${model_disp}${RESET}") ;;
    esac
fi

# Presupuesto para la rama: lo que sobra en `cols` tras el resto de L1. Descontamos el
# ancho visible del resto, un separador rama→resto (SEP_VLEN), el espacio inicial de la
# rama (1) y un margen (1). Solo truncamos si la rama no entra y hay al menos sitio para
# un prefijo legible; si el presupuesto es ínfimo (ventana diminuta) dejamos un piso.
btext="$branch"
if [ -n "$branch" ] && [ ${#rest_parts[@]} -gt 0 ]; then
    rest_joined=$(join_parts rest_parts)
    rest_len=$(visible_len "$rest_joined")
    branch_budget=$(( cols - rest_len - SEP_VLEN - 2 ))
    [ "$branch_budget" -lt 10 ] && branch_budget=10   # piso: prefijo + elipsis + algo de cola
    if [ "${#btext}" -gt "$branch_budget" ]; then
        btext=$(truncate_mid "$btext" "$branch_budget")
    fi
fi

parts=()
if [ -n "$branch" ]; then
    if [[ "$branch" == *"*" ]]; then
        parts+=("${C_DIRTY} ${btext}${RESET}")
    else
        parts+=("${C_BRANCH} ${btext}${RESET}")
    fi
fi
parts+=("${rest_parts[@]}")

# Effort, ctx, rl: preparar etiqueta normal + compacta
effort_label=""; effort_short=""; effort_color="$C_MODEL"
if [ -n "$effort" ]; then
    case "$effort" in
        low)    effort_label="effort:low";   effort_short="e:l"; effort_color="$C_MODEL" ;;
        medium) effort_label="effort:med";   effort_short="e:m"; effort_color="$C_MODEL" ;;
        high)   effort_label="effort:high";  effort_short="e:h"; effort_color="$C_EFFORT" ;;
        xhigh)  effort_label="effort:xhigh"; effort_short="e:x"; effort_color="$C_WARN" ;;
        max)    effort_label="effort:max";   effort_short="e:M"; effort_color="$C_CRIT" ;;
    esac
fi

ctx_label=""; ctx_short=""; ctx_color="$C_OK"
if [ -n "$ctx_tok" ] && [ -n "$ctx_size" ]; then
    ctx_tk=$(( (${ctx_tok%.*} + 500) / 1000 ))
    ctx_sk=$(( ${ctx_size%.*} / 1000 ))
    ctx_pct_int=${ctx_pct%.*}
    # Umbrales: 13%≈26K (mid-context blindness), 25%≈50K (rendimiento cae).
    if   [[ "$ctx_pct_int" =~ ^[0-9]+$ ]] && [ "$ctx_pct_int" -ge 25 ]; then ctx_color="$C_CRIT"
    elif [[ "$ctx_pct_int" =~ ^[0-9]+$ ]] && [ "$ctx_pct_int" -ge 13 ]; then ctx_color="$C_WARN"
    fi
    ctx_short="c:${ctx_tk}K"
    ctx_label="$ctx_short"
fi

rl_label=""; rl_short=""; rl_color="$C_MODEL"
if [ -n "$rl" ]; then
    rl_int=${rl%.*}
    # Claude Code a veces manda el timestamp `resets_at` en este campo (bug del CLI).
    # Solo mostrar si el valor es un porcentaje plausible (0-100).
    if [[ "$rl_int" =~ ^[0-9]+$ ]] && [ "$rl_int" -ge 0 ] && [ "$rl_int" -le 100 ]; then
        if   [ "$rl_int" -ge 80 ]; then rl_color="$C_CRIT"
        elif [ "$rl_int" -ge 50 ]; then rl_color="$C_WARN"
        fi
        rl_short="rl:${rl_int}%"
        if [ -n "$rl_resets" ] && [ "$rl_resets" != "null" ]; then
            now=$(date +%s)
            secs_left=$(( ${rl_resets%.*} - now ))
            if [ "$secs_left" -gt 0 ]; then
                h=$(( secs_left / 3600 ))
                m=$(( (secs_left % 3600) / 60 ))
                if [ "$h" -gt 0 ]; then
                    rl_short="rl:${rl_int}% ${h}h${m}m"
                else
                    rl_short="rl:${rl_int}% ${m}m"
                fi
            fi
        fi
        rl_label="$rl_short"
    fi
fi

# Línea 1: rama + path + server + modelo (ya construido en parts[])
# Línea 2: effort + ctx + rl (estado de la sesión)
extras=()
[ -n "$effort_short" ] && extras+=("${effort_color}${effort_short}${RESET}")
[ -n "$ctx_short" ]    && extras+=("${ctx_color}${ctx_short}${RESET}")
[ -n "$rl_short" ]     && extras+=("${rl_color}${rl_short}${RESET}")

line1=$(join_parts parts)
line2=$(join_parts extras)

len1=$(visible_len "$line1")
len2=$(visible_len "$line2")
total_one_line=$(( len1 + ${#extras[@]} > 0 ? len1 + 3 + len2 : len1 ))

# Si todo cabe en una sola línea, una sola; si no, dos líneas.
if [ ${#extras[@]} -eq 0 ]; then
    printf '%s' "$line1"
elif [ "$total_one_line" -le "$cols" ]; then
    if [ -n "$line1" ] && [ -n "$line2" ]; then
        printf '%s%s%s' "$line1" "$sep" "$line2"
    else
        printf '%s%s' "$line1" "$line2"
    fi
else
    printf '%s\n%s' "$line1" "$line2"
fi
