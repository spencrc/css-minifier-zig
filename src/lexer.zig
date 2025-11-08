const std = @import("std");

// Lexical analysis
// Each blob of characters in a sequence is a lexeme (raw subtrings of source code)
// Making lexemes also allows us to find tokens (keywords which shape language's grammar)

pub const TokenType = enum {
    IDENT,
    COMMENT,
    FUNCTION,
    AT_KEYWORD,
    HASH,
    STRING,
    BAD_STRING,
    URL,
    BAD_URL,
    DELIMITER,
    NUMBER,
    PERCENTAGE,
    DIMENSION,
    WHITESPACE,
    CDO,
    CDC,
    LEFT_SQUARE,
    RIGHT_SQUARE,
    LEFT_PAREN,
    RIGHT_PAREN,
    LEFT_CURLY,
    RIGHT_CURLY,
    COMMA,
    COLON,
    SEMICOLON,
    EOF,
};

pub const Token = struct {
    type: TokenType,
    lexeme: []const u8,
    literal: []const u8,

    pub fn init(t: TokenType, lexeme: []const u8, literal: []const u8) Token {
        return Token{
            .type = t,
            .lexeme = lexeme,
            .literal = literal,
        };
    }
};

pub const Scanner = struct {
    allocator: std.mem.Allocator,
    source: []const u8,
    tokens: std.ArrayList(Token) = .empty,
    start: usize = 0,
    current: usize = 0,

    pub fn init(allocator: std.mem.Allocator, source: []const u8) Scanner {
        return Scanner{
            .allocator = allocator,
            .source = source,
        };
    }

    pub fn deinit(self: *Scanner) void {
        self.tokens.deinit(self.allocator);
    }

    pub fn scan_tokens(self: *Scanner) !*std.ArrayList(Token) {
        while (!self.is_at_end()) {
            self.start = self.current;
            try self.scan_token();
        }

        try self.consume_token(.EOF);
        return &self.tokens;
    }

    fn scan_token(self: *Scanner) !void {
        const c = self.advance();
        switch (c) {
            '/' => {
                const current = self.peek() orelse {
                    try self.consume_token(.DELIMITER);
                    return;
                };
                if (current == '*') {
                    _ = self.advance();
                    self.consume_comment();
                } else try self.consume_token(.DELIMITER);
            },
            ' ', '\t', '\n', '\r', '\x0C' => {},
            '"' => try self.consume_string_token(),
            '(' => try self.consume_token(.LEFT_PAREN),
            ')' => try self.consume_token(.RIGHT_PAREN),
            '{' => try self.consume_token(.LEFT_CURLY),
            '}' => try self.consume_token(.RIGHT_CURLY),
            ',' => try self.consume_token(.COMMA),
            ';' => try self.consume_token(.SEMICOLON),
            '[' => try self.consume_token(.LEFT_SQUARE),
            ']' => try self.consume_token(.RIGHT_SQUARE),
            ':' => try self.consume_token(.COLON),
            '@' => {
                //if is the start of an identifier, scan at_keyword
                //else, add delimiter
            },
            '#' => {
                //if is a hash, scan hash
                //else, add delimiter
            },
            '>', '+', '!', '=', '%', '~', '|', '^', '$', '*', '.' => try self.consume_token(.DELIMITER),
            //TODO: add < for <!-- --> scanning
            else => {
                if (isIdentStartCodePoint(c)) {
                    try self.consume_identlike_token();
                } else if (std.ascii.isDigit(c)) {
                    try self.consume_numeric_token();
                } else {
                    std.log.err("Unexpected char: <{c}>", .{c});
                    return error.UnexpectedCharacter;
                }
            },
        }
    }

    fn consume_token(self: *Scanner, t: TokenType) !void {
        try self.add_token(t, "");
    }

    fn consume_comment(self: *Scanner) void {
        while (!self.is_at_end()) {
            const current = self.peek() orelse break;
            const next = self.peek_ahead(1) orelse break;
            if (current == '*' and next == '/') {
                _ = self.advance();
                _ = self.advance();
                break;
            }
            _ = self.advance();
        }
    }

    fn consume_numeric_token(self: *Scanner) !void {
        const result = try self.consume_number();
        try self.add_token(.NUMBER, result);
    }

    fn consume_identlike_token(self: *Scanner) !void {
        const result = try self.consume_ident_sequence();
        try self.add_token(.IDENT, result);
    }

    fn consume_string_token(self: *Scanner) !void {
        //this skips the first quotation mark, as it was consumed in scan_token (meaning it's located at self.start)
        while (!self.is_at_end()) {
            const c = self.advance();
            switch (c) {
                '"' => {
                    try self.add_token(.STRING, self.source[self.start..self.current]);
                    return;
                }, //closing quotation marks
                '\n' => {
                    try self.add_token(.BAD_STRING, self.source[self.start..self.current]);
                    return;
                },
                //need to handle escape sequences other than \n here!
                else => continue,
            }
        }
        //No closing quote at EOF, bad string
        try self.add_token(.BAD_STRING, self.source[self.start..self.current]);
    }

    fn consume_ident_sequence(self: *Scanner) ![]const u8 {
        while (!self.is_at_end()) {
            const c = self.peek() orelse break;
            if (isIdentStartCodePoint(c) or std.ascii.isDigit(c) or c == '-') {
                _ = self.advance();
            } else {
                break;
            }
            //need to handle escape sequences here!
        }
        return self.source[self.start..self.current];
    }

    fn consume_number(self: *Scanner) ![]const u8 {
        var current = self.peek() orelse return self.source[self.start..self.current];
        var next_1: u8 = undefined;
        var next_2: u8 = undefined;

        if (current == '+' or current == '-') {
            _ = self.advance();
            current = self.peek() orelse return self.source[self.start..self.current];
        }

        while (!self.is_at_end() and std.ascii.isDigit(current)) {
            _ = self.advance();
            current = self.peek() orelse return self.source[self.start..self.current];
        }

        next_1 = self.peek_ahead(1) orelse return self.source[self.start..self.current];
        if (current == '.' and std.ascii.isDigit(next_1)) {
            _ = self.advance();
            _ = self.advance();
            current = self.peek() orelse return self.source[self.start..self.current];
            while (!self.is_at_end() and std.ascii.isDigit(current)) {
                _ = self.advance();
                current = self.peek() orelse return self.source[self.start..self.current];
            }
        }

        next_1 = self.peek_ahead(1) orelse return self.source[self.start..self.current];
        if (current == 'E' or current == 'e') {
            if (next_1 == '-' or next_1 == '+') {
                next_2 = self.peek_ahead(2) orelse return self.source[self.start..self.current];
                if (std.ascii.isDigit(next_2)) {
                    _ = self.advance();
                    _ = self.advance();
                    _ = self.advance();
                    current = self.peek() orelse return self.source[self.start..self.current];
                    while (!self.is_at_end() and std.ascii.isDigit(current)) {
                        _ = self.advance();
                        current = self.peek() orelse return self.source[self.start..self.current];
                    }
                }
            } else if (std.ascii.isDigit(next_1)) {
                _ = self.advance();
                _ = self.advance();
                current = self.peek() orelse return self.source[self.start..self.current];
                while (!self.is_at_end() and std.ascii.isDigit(current)) {
                    _ = self.advance();
                    current = self.peek() orelse return self.source[self.start..self.current];
                }
            }
        }
        return self.source[self.start..self.current];
    }

    fn add_token(self: *Scanner, t: TokenType, literal: []const u8) !void {
        const new_token = Token.init(t, self.source[self.start..self.current], literal);
        try self.tokens.append(self.allocator, new_token);
    }

    fn is_at_end(self: *Scanner) bool {
        return self.current >= self.source.len;
    }

    fn advance(self: *Scanner) u8 {
        const c: u8 = self.source[self.current];
        self.current += 1;
        return c;
    }

    fn peek(self: *Scanner) ?u8 {
        if (self.is_at_end())
            return null;
        return self.source[self.current];
    }

    fn peek_ahead(self: *Scanner, offset: usize) ?u8 {
        if (self.current + offset >= self.source.len)
            return null;
        return self.source[self.current + offset];
    }

    fn isIdentStartCodePoint(c: u8) bool {
        return std.ascii.isAlphabetic(c) or c >= 0x80 or c == '_';
    }
};
