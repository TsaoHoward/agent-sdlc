const fs = require("fs");

function parseScalar(value) {
  if (value === "[]") {
    return [];
  }

  if (value === "{}") {
    return {};
  }

  if (value === "true") {
    return true;
  }

  if (value === "false") {
    return false;
  }

  if (/^-?\d+$/.test(value)) {
    return Number(value);
  }

  if (
    (value.startsWith('"') && value.endsWith('"')) ||
    (value.startsWith("'") && value.endsWith("'"))
  ) {
    return value.slice(1, -1);
  }

  return value;
}

function splitKeyValue(text, lineNumber) {
  const separatorIndex = text.indexOf(":");
  if (separatorIndex === -1) {
    throw new Error(`Expected a key/value pair on line ${lineNumber}.`);
  }

  return {
    key: text.slice(0, separatorIndex).trim(),
    valueText: text.slice(separatorIndex + 1).trim(),
  };
}

function parseYaml(text) {
  const lines = text.replace(/\r\n/g, "\n").split("\n");
  let index = 0;

  function nextRelevantLine(startIndex) {
    let cursor = startIndex;
    while (cursor < lines.length) {
      const trimmed = lines[cursor].trim();
      if (trimmed !== "" && !trimmed.startsWith("#")) {
        break;
      }

      cursor += 1;
    }

    return cursor;
  }

  function getIndent(rawLine, lineNumber) {
    const match = rawLine.match(/^[ ]*/u);
    const indent = match ? match[0] : "";
    if (indent.includes("\t")) {
      throw new Error(`Tabs are not supported in YAML indentation on line ${lineNumber}.`);
    }

    return indent.length;
  }

  function parseBlock(expectedIndent) {
    index = nextRelevantLine(index);
    if (index >= lines.length) {
      return null;
    }

    const rawLine = lines[index];
    const lineNumber = index + 1;
    const indent = getIndent(rawLine, lineNumber);

    if (indent < expectedIndent) {
      return null;
    }

    if (indent !== expectedIndent) {
      throw new Error(
        `Unexpected indentation on line ${lineNumber}. Expected ${expectedIndent} spaces but found ${indent}.`,
      );
    }

    if (rawLine.trim().startsWith("- ")) {
      return parseArray(expectedIndent);
    }

    return parseObject(expectedIndent, {});
  }

  function parseObject(expectedIndent, seedObject) {
    const objectValue = seedObject;

    while (true) {
      index = nextRelevantLine(index);
      if (index >= lines.length) {
        break;
      }

      const rawLine = lines[index];
      const lineNumber = index + 1;
      const indent = getIndent(rawLine, lineNumber);
      const trimmed = rawLine.trim();

      if (indent < expectedIndent) {
        break;
      }

      if (indent !== expectedIndent) {
        throw new Error(
          `Unexpected indentation on line ${lineNumber}. Expected ${expectedIndent} spaces but found ${indent}.`,
        );
      }

      if (trimmed.startsWith("- ")) {
        break;
      }

      const { key, valueText } = splitKeyValue(trimmed, lineNumber);
      index += 1;

      if (valueText === "") {
        const nestedValue = parseBlock(expectedIndent + 2);
        objectValue[key] = nestedValue === null ? null : nestedValue;
      } else {
        objectValue[key] = parseScalar(valueText);
      }
    }

    return objectValue;
  }

  function parseArray(expectedIndent) {
    const arrayValue = [];

    while (true) {
      index = nextRelevantLine(index);
      if (index >= lines.length) {
        break;
      }

      const rawLine = lines[index];
      const lineNumber = index + 1;
      const indent = getIndent(rawLine, lineNumber);
      const trimmed = rawLine.trim();

      if (indent < expectedIndent) {
        break;
      }

      if (indent !== expectedIndent) {
        throw new Error(
          `Unexpected indentation on line ${lineNumber}. Expected ${expectedIndent} spaces but found ${indent}.`,
        );
      }

      if (!trimmed.startsWith("- ")) {
        break;
      }

      const itemText = trimmed.slice(2).trim();
      index += 1;

      if (itemText === "") {
        const nestedValue = parseBlock(expectedIndent + 2);
        arrayValue.push(nestedValue);
        continue;
      }

      if (itemText.includes(":")) {
        const { key, valueText } = splitKeyValue(itemText, lineNumber);
        const objectItem = {};

        if (valueText === "") {
          const nestedValue = parseBlock(expectedIndent + 4);
          objectItem[key] = nestedValue === null ? null : nestedValue;
        } else {
          objectItem[key] = parseScalar(valueText);
        }

        arrayValue.push(parseObject(expectedIndent + 2, objectItem));
        continue;
      }

      arrayValue.push(parseScalar(itemText));
    }

    return arrayValue;
  }

  const parsed = parseBlock(0);
  return parsed === null ? {} : parsed;
}

function readYamlFile(filePath) {
  return parseYaml(fs.readFileSync(filePath, "utf8"));
}

module.exports = {
  parseYaml,
  readYamlFile,
};
