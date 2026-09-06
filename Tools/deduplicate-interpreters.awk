BEGIN {
    FPAT = "([^,]*)|(\"([^\"]|\"\")+\")"
}

function decode_csv(value) {
    if (substr(value, 1, 1) == "\"" && substr(value, length(value), 1) == "\"") {
        value = substr(value, 2, length(value) - 2)
        gsub(/""/, "\"", value)
    }
    return value
}

function encode_csv(value, encoded) {
    encoded = value
    gsub(/"/, "\"\"", encoded)
    return "\"" encoded "\""
}

{
    path = decode_csv($1)
    volume = decode_csv($2)

    # Path, volume, and comment do not participate in duplicate identity.
    key = ""
    for (field = 4; field <= NF; field++) {
        value = decode_csv($field)
        key = key length(value) ":" value
    }

    if (!(key in row_number)) {
        row_count++
        row_number[key] = row_count
        keys[row_count] = key
        field_counts[row_count] = NF
        for (field = 1; field <= NF; field++) {
            values[row_count, field] = decode_csv($field)
        }
        next
    }

    row = row_number[key]
    duplicate = path
    if (volume != "") duplicate = duplicate " (volume: " volume ")"
    if (values[row, 3] == "") {
        values[row, 3] = "Also found at: " duplicate
    } else {
        values[row, 3] = values[row, 3] "; " duplicate
    }
}

END {
    for (row = 1; row <= row_count; row++) {
        output = ""
        for (field = 1; field <= field_counts[row]; field++) {
            if (field > 1) output = output ","
            output = output encode_csv(values[row, field])
        }
        print output
    }
}
