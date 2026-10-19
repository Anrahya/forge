/**
 * A deliberately small TOML reader for forge.toml. Pure, no dependency.
 *
 * Supported: comments, `[table]` and `[a.b]` headers (the dotted name is kept
 * as one literal key), bare and quoted keys, basic and literal strings,
 * integers, floats, booleans, and arrays of those (single or multi-line).
 * Anything else (inline tables, dates, multi-line strings, array-of-tables)
 * is an error naming the line, so a typo never silently drops a setting.
 */
export type TomlValue = string | number | boolean | TomlValue[];
export type TomlTables = Record<string, Record<string, TomlValue>>;
export declare class TomlError extends Error {
    readonly line: number;
    constructor(line: number, message: string);
}
/**
 * Parse TOML text into `{ table: { key: value } }`. Keys before the first
 * header land in the `""` table.
 */
export declare function parseToml(text: string): TomlTables;
