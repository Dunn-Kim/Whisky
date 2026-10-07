//
//  TextTable.swift
//  WhiskyCmd
//
//  This file is part of Whisky.
//
//  Whisky is free software: you can redistribute it and/or modify it under the terms
//  of the GNU General Public License as published by the Free Software Foundation,
//  either version 3 of the License, or (at your option) any later version.
//
//  Whisky is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
//  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License along with Whisky.
//  If not, see https://www.gnu.org/licenses/.
//

import Foundation

// MARK: - Terminal Display Width Calculation

extension String {
    /// The number of cells the string occupies in a terminal: `wcwidth` per
    /// scalar, with non-printables (a negative width) counted as zero.
    var terminalWidth: Int {
        unicodeScalars.reduce(0) { $0 + max(0, Int(wcwidth(wchar_t($1.value)))) }
    }

    /// Pad the string with spaces to a specific terminal width
    /// - Parameter targetWidth: The desired terminal display width
    /// - Returns: A string padded to the target terminal width
    func terminalPadding(toWidth targetWidth: Int) -> String {
        let currentWidth = self.terminalWidth
        if currentWidth >= targetWidth {
            return self
        }
        let paddingNeeded = targetWidth - currentWidth
        return self + String(repeating: " ", count: paddingNeeded)
    }
}

// MARK: - TextTable

/// A simple text table generator for CLI output
struct TextTable {
    /// Represents a column in the table
    struct Column {
        let header: String
        var width: Int

        init(header: String) {
            self.header = header
            self.width = header.terminalWidth
        }
    }

    private var columns: [Column]
    private var rows: [[String]]

    /// Initialize a new text table with the given headers
    /// - Parameter headers: An array of header strings for each column
    init(headers: [String]) {
        // wcwidth answers for LC_CTYPE, which is "C" (every non-ASCII scalar
        // unprintable) unless set. UTF-8 rather than the environment's, so CJK
        // stays two cells wide when LANG is unset.
        setlocale(LC_CTYPE, "UTF-8")
        self.columns = headers.map { Column(header: $0) }
        self.rows = []
    }

    /// Add a row of values to the table
    /// - Parameter values: An array of string values, one for each column
    mutating func addRow(values: [String]) {
        // Pad or truncate the values array to match the number of columns
        var adjustedValues = values
        while adjustedValues.count < columns.count {
            adjustedValues.append("")
        }
        if adjustedValues.count > columns.count {
            adjustedValues = Array(adjustedValues.prefix(columns.count))
        }

        // Update column widths based on the new values (using terminal width)
        for (index, value) in adjustedValues.enumerated() {
            columns[index].width = max(columns[index].width, value.terminalWidth)
        }

        rows.append(adjustedValues)
    }

    /// Render the table as a formatted string
    /// - Returns: A string representation of the table with ASCII borders
    func render() -> String {
        guard !columns.isEmpty else { return "" }

        var lines: [String] = []

        // Create the separator line
        let separator = "+" + columns.map { String(repeating: "-", count: $0.width + 2) }.joined(separator: "+") + "+"

        // Add top border
        lines.append(separator)

        // Add header row (using terminal-aware padding)
        let headerRow = "|" + columns.map { column in
            " " + column.header.terminalPadding(toWidth: column.width) + " "
        }.joined(separator: "|") + "|"
        lines.append(headerRow)

        // Add header separator
        lines.append(separator)

        // Add data rows (using terminal-aware padding)
        for row in rows {
            let dataRow = "|" + zip(columns, row).map { column, value in
                " " + value.terminalPadding(toWidth: column.width) + " "
            }.joined(separator: "|") + "|"
            lines.append(dataRow)
        }

        // Add bottom border
        lines.append(separator)

        return lines.joined(separator: "\n")
    }
}
