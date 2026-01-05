#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

die () {

    local msg="${1:-}"
    local code="${2:-1}"

    printf '%s\n' "${msg}" >&2

    if [[ "${-}" == *i* ]]; then
        return "${code}"
    fi

    exit "${code}"

}
parse_require_bash () {

    [[ -n "${BASH_VERSINFO[0]-}" ]] || die "parse: bash required" 2

    local major="${BASH_VERSINFO[0]}"
    local minor="${BASH_VERSINFO[1]}"

    if (( major < 4 || ( major == 4 && minor < 3 ) )); then
        die "parse: requires bash >= 4.3 (nameref support)" 2
    fi

    return 0

}
parse_norm_key () {

    local k="${1-}"

    k="${k#--}"
    k="${k#-}"
    k="${k//-/_}"

    [[ -n "${k}" ]] || die "parse: empty key" 2
    [[ "${k}" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || die "parse: invalid key '${k}'" 2

    printf '%s' "${k}"
    return 0

}
parse_is_schema_token () {

    local s="${1-}"
    [[ "${s}" =~ ^:?(--|-)?[a-zA-Z_][a-zA-Z0-9_-]*(\|(--|-)?[a-zA-Z_][a-zA-Z0-9_-]*)*(:(int|float|str|char|bool|list|any))?$ ]]

}
parse_is_int () {

    [[ "${1-}" =~ ^[+-]?[0-9]+$ ]]

}
parse_is_float () {

    [[ "${1-}" =~ ^[+-]?([0-9]+([.][0-9]+)?|[.][0-9]+)$ ]]

}
parse_int_norm () {

    local v="${1-}"
    local label="${2-int}"

    [[ -n "${v}" ]] || die "parse: '${label}' must be an integer (no decimals)" 2

    parse_is_int "${v}" && { printf '%s' "${v}"; return 0; }

    if [[ "${v}" =~ ^([+-]?[0-9]+)[.](0+)$ ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        return 0
    fi

    die "parse: '${label}' must be an integer (no decimals)" 2

}
parse_bool_norm () {

    local v="${1-}"
    local label="${2-bool}"

    [[ -n "${v}" ]] || die "parse: '${label}' must be 'true' or 'false' (or 1/0)" 2

    v="${v,,}"

    case "${v}" in
        1|true|yes|y|on|t)  printf '1' ;;
        0|false|no|n|off|f) printf '0' ;;
        *) die "parse: '${label}' must be 'true' or 'false' (or 1/0)" 2 ;;
    esac

    return 0

}
parse_set_scalar () {

    local __p_key="${1-}"
    local __p_val="${2-}"

    printf -v "${__p_key}" '%s' "${__p_val}"

    return 0

}
parse_set_array () {

    local __p_key="${1-}"
    shift || true

    local -n __p_ref="${__p_key}"

    __p_ref=()

    if (( $# )); then
        __p_ref+=( "$@" )
    fi

    return 0

}
parse_array_append () {

    local __p_key="${1-}"
    local __p_val="${2-}"

    local -n __p_ref="${__p_key}"

    __p_ref+=( "${__p_val}" )

    return 0

}
parse_args_split () {

    local -n out_argv="${1}"
    local -n out_schema="${2}"
    shift 2 || true

    out_argv=()
    out_schema=()

    local -a all=( "$@" )
    local sep=-1
    local i=0

    for (( i=${#all[@]}-1; i>=0; i-- )); do
        if [[ "${all[$i]}" == "--" ]]; then
            sep=$i
            break
        fi
    done

    (( sep >= 0 )) || die "parse: missing '--' separator" 2

    out_argv=( "${all[@]:0:$sep}" )
    out_schema=( "${all[@]:$(( sep + 1 ))}" )

    (( ${#out_schema[@]} )) || die "parse: missing schema" 2

    return 0

}
parse () {

    parse_require_bash

    local -a argv=()
    local -a schema=()

    parse_args_split argv schema "$@"
    (( ${#schema[@]} )) || die "parse: missing schema" 2

    local -A stype=()
    local -A sreq=()
    local -A set=()
    local -A alias_to=()
    local -A sdisp=()

    local -a order=()
    local -a pos_order=()

    local spec="" raw="" names="" canon="" nk="" kind="" t=""
    local req=0
    local -a name_list=()
    local nm="" ak=""

    for spec in "${schema[@]}"; do

        parse_is_schema_token "${spec}" || die "parse: bad schema token '${spec}'" 2

        raw="${spec}"
        req=0

        if [[ "${raw}" == :* ]]; then
            req=1
            raw="${raw#:}"
        fi

        if [[ "${raw}" == *:* ]]; then
            t="${raw##*:}"
            names="${raw%:*}"
        else
            t="str"
            names="${raw}"
        fi

        case "${t}" in
            int|float|str|char|bool|list|any) ;;
            *) die "parse: unknown type '${t}' for '${spec}'" 2 ;;
        esac

        IFS='|' read -r -a name_list <<< "${names}"
        (( ${#name_list[@]} )) || die "parse: bad schema '${spec}'" 2

        canon="${name_list[0]}"
        [[ "${canon}" != --no-* && "${canon}" != -no-* ]] || die "parse: schema name '${canon}' is reserved (no- prefix)" 2

        nk="$(parse_norm_key "${canon}")"
        [[ "${nk}" != __* ]] || die "parse: key '${canon}' is reserved (internal prefix)" 2

        case "${nk}" in
            argv|schema|stype|sreq|set|alias_to|sdisp|order|pos_order|pos|spec|raw|names|canon|nk|kind|t|req|name_list|nm|ak|i|pi|pn|pv|arg|key|val|next|k|tv|n|p|vv|x)
                die "parse: key '${canon}' is reserved" 2
            ;;
        esac

        [[ -z "${stype[${nk}]-}" ]] || die "parse: duplicate name '${nk}'" 2

        stype["${nk}"]="${t}"
        sreq["${nk}"]="${req}"
        sdisp["${nk}"]="${canon}"

        order+=( "${nk}" )

        kind="pos"
        if [[ "${canon}" == --* ]]; then
            kind="long"
        elif [[ "${canon}" == -* ]]; then
            kind="short"
        fi

        if [[ "${kind}" == "pos" ]]; then
            pos_order+=( "${nk}" )
        fi

        for nm in "${name_list[@]-}"; do

            ak="$(parse_norm_key "${nm}")"

            if [[ -n "${alias_to[${ak}]-}" ]]; then
                [[ "${alias_to[${ak}]}" == "${nk}" ]] || die "parse: duplicate alias '${nm}'" 2
                continue
            fi

            alias_to["${ak}"]="${nk}"

        done

    done

    local i=0
    local p=""

    for (( i=0; i<${#pos_order[@]}-1; i++ )); do
        p="${pos_order[$i]}"
        [[ "${stype[${p}]}" == "list" ]] && die "parse: positional '${sdisp[${p}]}' (list) must be last" 2
    done

    local n="" tv=""

    for n in "${order[@]}"; do

        tv="${stype[${n}]}"

        case "${tv}" in
            int)   parse_set_scalar "${n}" "0" ;;
            float) parse_set_scalar "${n}" "0.0" ;;
            bool)  parse_set_scalar "${n}" "0" ;;
            list)  parse_set_array  "${n}" ;;
            char|str|any) parse_set_scalar "${n}" "" ;;
        esac

    done

    local -a pos=()
    local arg="" key="" val="" next="" k=""

    i=0
    while (( i < ${#argv[@]} )); do

        arg="${argv[$i]}"
        i=$(( i + 1 ))

        if [[ "${arg}" == "--" ]]; then
            while (( i < ${#argv[@]} )); do
                pos+=( "${argv[$i]}" )
                i=$(( i + 1 ))
            done
            break
        fi
        if [[ "${arg}" =~ ^-[0-9] || "${arg}" =~ ^-\.[0-9] ]]; then
            pos+=( "${arg}" )
            continue
        fi

        case "${arg}" in
            --no-*|-no-*)
                key="${arg#--no-}"
                key="${key#-no-}"

                k="$(parse_norm_key "${key}")"
                k="${alias_to[${k}]-}"

                [[ -n "${k}" ]] || die "parse: unknown option '${arg}'" 2
                [[ "${stype[${k}]}" == "bool" ]] || die "parse: '${arg}' requires bool" 2

                parse_set_scalar "${k}" "0"
                set["${k}"]=1
                continue
            ;;
            --*=*|-*=*)
                key="${arg%%=*}"
                val="${arg#*=}"

                if [[ "${key}" == --* ]]; then
                    key="${key#--}"
                elif [[ "${key}" == -* ]]; then
                    key="${key#-}"
                fi

                k="$(parse_norm_key "${key}")"
                k="${alias_to[${k}]-}"

                [[ -n "${k}" ]] || die "parse: unknown key '${key}'" 2
                tv="${stype[${k}]}"

                if [[ "${tv}" == "bool" ]]; then
                    val="$(parse_bool_norm "${val}" "${sdisp[${k}]}" )"
                    parse_set_scalar "${k}" "${val}"
                elif [[ "${tv}" == "int" ]]; then
                    val="$(parse_int_norm "${val}" "${sdisp[${k}]}" )"
                    parse_set_scalar "${k}" "${val}"
                elif [[ "${tv}" == "list" ]]; then
                    parse_array_append "${k}" "${val}"
                else
                    parse_set_scalar "${k}" "${val}"
                fi

                set["${k}"]=1
                continue
            ;;
            --*|-*)
                if [[ "${arg}" == --* ]]; then
                    key="${arg#--}"
                else
                    key="${arg#-}"
                fi

                k="$(parse_norm_key "${key}")"
                k="${alias_to[${k}]-}"

                [[ -n "${k}" ]] || die "parse: unknown option '${arg}'" 2

                tv="${stype[${k}]}"

                if [[ "${tv}" == "bool" ]]; then

                    if (( i < ${#argv[@]} )) && [[ "${argv[$i]}" != --* && "${argv[$i]}" != -* ]]; then
                        val="$(parse_bool_norm "${argv[$i]}" "${sdisp[${k}]}" )"
                        parse_set_scalar "${k}" "${val}"
                        i=$(( i + 1 ))
                    else
                        parse_set_scalar "${k}" "1"
                    fi

                    set["${k}"]=1
                    continue

                fi

                (( i < ${#argv[@]} )) || die "parse: '${arg}' expects a value" 2
                next="${argv[$i]}"

                if [[ "${next}" == --* || "${next}" == -* ]]; then
                    die "parse: '${arg}' expects a value (use ${arg}=VALUE for values starting with '-')" 2
                fi

                i=$(( i + 1 ))

                if [[ "${tv}" == "int" ]]; then
                    next="$(parse_int_norm "${next}" "${sdisp[${k}]}" )"
                fi

                if [[ "${tv}" == "list" ]]; then
                    parse_array_append "${k}" "${next}"
                else
                    parse_set_scalar "${k}" "${next}"
                fi

                set["${k}"]=1
                continue
            ;;

            *)
                pos+=( "${arg}" )
                continue
            ;;
        esac

    done

    local pi=0
    local pn="" pv=""

    for pn in "${pos_order[@]-}"; do

        tv="${stype[${pn}]}"
        [[ -n "${tv}" ]] || continue

        if [[ "${tv}" == "list" ]]; then

            if [[ -z "${set[${pn}]-}" ]]; then
                parse_set_array "${pn}"
                set["${pn}"]=1
            fi

            local x=""
            for x in "${pos[@]:$pi}"; do
                parse_array_append "${pn}" "${x}"
            done

            pi="${#pos[@]}"
            break

        fi
        if [[ -n "${set[${pn}]-}" ]]; then
            continue
        fi
        if (( pi >= ${#pos[@]} )); then
            continue
        fi

        pv="${pos[$pi]}"
        pi=$(( pi + 1 ))

        case "${tv}" in
            int)   pv="$(parse_int_norm "${pv}" "${sdisp[${pn}]}" )" ;;
            float) parse_is_float "${pv}" || die "parse: '${sdisp[${pn}]}' must be a float number" 2 ;;
            bool)  pv="$(parse_bool_norm "${pv}" "${sdisp[${pn}]}" )" ;;
            char)  [[ "${#pv}" -eq 1 ]] || die "parse: '${sdisp[${pn}]}' must be exactly 1 character" 2 ;;
        esac

        parse_set_scalar "${pn}" "${pv}"
        set["${pn}"]=1

    done

    if (( pi < ${#pos[@]} )); then
        die "parse: unexpected positional args: ${pos[*]:$pi}" 2
    fi

    for n in "${order[@]}"; do

        tv="${stype[${n}]}"

        if (( sreq[${n}] )); then
            [[ -n "${set[${n}]-}" ]] || die "parse: missing required '${sdisp[${n}]}'" 2
        fi

        [[ -n "${set[${n}]-}" ]] || continue

        case "${tv}" in
            int)   parse_set_scalar "${n}" "$(parse_int_norm "${!n-}" "${sdisp[${n}]}" )" ;;
            float) parse_is_float "${!n-}" || die "parse: '${sdisp[${n}]}' must be a float number" 2 ;;
            bool)  parse_set_scalar "${n}" "$(parse_bool_norm "${!n-}" "${sdisp[${n}]}" )" ;;
            char)
                local vv="${!n-}"
                if (( sreq[${n}] )); then
                    [[ "${#vv}" -eq 1 ]] || die "parse: '${sdisp[${n}]}' must be exactly 1 character" 2
                else
                    if [[ -n "${vv}" ]]; then
                        [[ "${#vv}" -eq 1 ]] || die "parse: '${sdisp[${n}]}' must be exactly 1 character" 2
                    fi
                fi
            ;;
            str|any)
                if (( sreq[${n}] )); then
                    [[ -n "${!n-}" ]] || die "parse: '${sdisp[${n}]}' can't be empty" 2
                fi
            ;;
            list)
                if (( sreq[${n}] )); then
                    local -n r="${n}"
                    (( ${#r[@]} )) || die "parse: missing required '${sdisp[${n}]}'" 2
                fi
            ;;
        esac

    done

    return 0

}

# main () {

#     parse "$@" -- type:char :name:str role:int age:float active:bool opt:any :date salary :data:list

#     printf "type=%s\n" "${type}"
#     printf "name=%s\n" "${name}"
#     printf "role=%s\n" "${role}"
#     printf "age=%s\n"  "${age}"
#     printf "active=%s\n" "${active}"
#     printf "date=%s\n" "${date}"
#     printf "salary=%s\n" "${salary}"
#     printf "opt=%s\n" "${opt}"

#     printf "data_count=%s\n" "${#data[@]}"

#     {
#         local IFS=' '
#         printf "data=%s\n" "${data[*]-}"
#     }

# }
# main  A "Coding Master" 7 21.5 true hello 2026-01-05 9000 x y z --type s
# main --name "welcome" --date "2026-01-05" --active true --data=x --data=y --data=z --opt 23.2 --role 120.0 --type A
