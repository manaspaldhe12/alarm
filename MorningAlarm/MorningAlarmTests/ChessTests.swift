import XCTest
@testable import MorningAlarm

final class ChessTests: XCTestCase {
    func testSquareAlgebraicRoundTrip() {
        let square = ChessSquare(algebraic: "e4")
        XCTAssertNotNil(square)
        XCTAssertEqual(square?.file, 4)
        XCTAssertEqual(square?.rank, 3)
        XCTAssertEqual(square?.algebraic, "e4")
    }

    func testSquareRejectsOutOfRange() {
        XCTAssertNil(ChessSquare(algebraic: "z9"))
        XCTAssertNil(ChessSquare(algebraic: "a0"))
        XCTAssertNil(ChessSquare(algebraic: ""))
    }

    func testMoveUCIParsingWithoutPromotion() {
        let move = ChessMove(uci: "e2e4")
        XCTAssertNotNil(move)
        XCTAssertEqual(move?.from, ChessSquare(algebraic: "e2"))
        XCTAssertEqual(move?.to, ChessSquare(algebraic: "e4"))
        XCTAssertNil(move?.promotion)
        XCTAssertEqual(move?.uci, "e2e4")
    }

    func testMoveUCIParsingWithPromotion() {
        let move = ChessMove(uci: "e7e8q")
        XCTAssertNotNil(move)
        XCTAssertEqual(move?.promotion, .queen)
        XCTAssertEqual(move?.uci, "e7e8q")
    }

    func testMoveRejectsMalformedUCI() {
        XCTAssertNil(ChessMove(uci: "e2"))
        XCTAssertNil(ChessMove(uci: "e2e4qq"))
    }

    func testBoardParsesStartingPosition() {
        let board = ChessBoard(fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")
        XCTAssertEqual(board.sideToMove, .white)
        XCTAssertEqual(board.piece(at: ChessSquare(algebraic: "e1")!), ChessPiece(kind: .king, color: .white))
        XCTAssertEqual(board.piece(at: ChessSquare(algebraic: "e8")!), ChessPiece(kind: .king, color: .black))
        XCTAssertEqual(board.piece(at: ChessSquare(algebraic: "a1")!), ChessPiece(kind: .rook, color: .white))
        XCTAssertEqual(board.piece(at: ChessSquare(algebraic: "e2")!), ChessPiece(kind: .pawn, color: .white))
        XCTAssertNil(board.piece(at: ChessSquare(algebraic: "e4")!))
    }

    func testBoardParsesBlackToMove() {
        let board = ChessBoard(fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1")
        XCTAssertEqual(board.sideToMove, .black)
    }

    func testBoardAppliesSimplePawnMove() {
        var board = ChessBoard(fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")
        board.apply(ChessMove(uci: "e2e4")!)
        XCTAssertNil(board.piece(at: ChessSquare(algebraic: "e2")!))
        XCTAssertEqual(board.piece(at: ChessSquare(algebraic: "e4")!), ChessPiece(kind: .pawn, color: .white))
        XCTAssertEqual(board.sideToMove, .black, "applying a move should flip the side to move")
    }

    func testBoardAppliesCapture() {
        // White pawn e4, black pawn d5 — exd5 should remove the black pawn and place the white one on d5.
        var board = ChessBoard(fen: "rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 1")
        board.apply(ChessMove(uci: "e4d5")!)
        XCTAssertEqual(board.piece(at: ChessSquare(algebraic: "d5")!), ChessPiece(kind: .pawn, color: .white))
        XCTAssertNil(board.piece(at: ChessSquare(algebraic: "e4")!))
    }

    func testBoardAppliesKingsideCastling() {
        // White king e1, rook h1, empty f1/g1.
        var board = ChessBoard(fen: "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
        board.apply(ChessMove(uci: "e1g1")!)
        XCTAssertEqual(board.piece(at: ChessSquare(algebraic: "g1")!), ChessPiece(kind: .king, color: .white))
        XCTAssertEqual(board.piece(at: ChessSquare(algebraic: "f1")!), ChessPiece(kind: .rook, color: .white))
        XCTAssertNil(board.piece(at: ChessSquare(algebraic: "e1")!))
        XCTAssertNil(board.piece(at: ChessSquare(algebraic: "h1")!))
    }

    func testBoardAppliesQueensideCastling() {
        var board = ChessBoard(fen: "r3k2r/8/8/8/8/8/8/R3K2R b KQkq - 0 1")
        board.apply(ChessMove(uci: "e8c8")!)
        XCTAssertEqual(board.piece(at: ChessSquare(algebraic: "c8")!), ChessPiece(kind: .king, color: .black))
        XCTAssertEqual(board.piece(at: ChessSquare(algebraic: "d8")!), ChessPiece(kind: .rook, color: .black))
        XCTAssertNil(board.piece(at: ChessSquare(algebraic: "e8")!))
        XCTAssertNil(board.piece(at: ChessSquare(algebraic: "a8")!))
    }

    func testBoardAppliesEnPassant() {
        // White pawn on e5, black just played d7-d5 (so black pawn sits on d5, en-passant target d6).
        var board = ChessBoard(fen: "rnbqkbnr/ppp1pppp/8/3pP3/8/8/PPPP1PPP/RNBQKBNR w KQkq d6 0 1")
        board.apply(ChessMove(uci: "e5d6")!)
        XCTAssertEqual(board.piece(at: ChessSquare(algebraic: "d6")!), ChessPiece(kind: .pawn, color: .white))
        XCTAssertNil(board.piece(at: ChessSquare(algebraic: "d5")!), "the captured black pawn should be removed")
        XCTAssertNil(board.piece(at: ChessSquare(algebraic: "e5")!))
    }

    func testBoardAppliesPromotion() {
        var board = ChessBoard(fen: "8/4P3/8/8/8/8/8/4K2k w - - 0 1")
        board.apply(ChessMove(uci: "e7e8q")!)
        XCTAssertEqual(board.piece(at: ChessSquare(algebraic: "e8")!), ChessPiece(kind: .queen, color: .white))
    }

    func testEngineAcceptsCorrectFirstMove() {
        let puzzle = Puzzle(id: "p1", rating: 700, fen: "8/8/8/8/8/8/4P3/4K2k w - - 0 1", sideToMove: .white, solution: ["e2e4"])
        let engine = LocalChessEngine()
        XCTAssertTrue(engine.validate(move: ChessMove(uci: "e2e4")!, puzzle: puzzle, solvedMoveCount: 0))
    }

    func testEngineRejectsWrongMove() {
        let puzzle = Puzzle(id: "p1", rating: 700, fen: "8/8/8/8/8/8/4P3/4K2k w - - 0 1", sideToMove: .white, solution: ["e2e4"])
        let engine = LocalChessEngine()
        XCTAssertFalse(engine.validate(move: ChessMove(uci: "e2e3")!, puzzle: puzzle, solvedMoveCount: 0))
    }

    func testEngineRejectsMoveBeyondSolutionLength() {
        let puzzle = Puzzle(id: "p1", rating: 700, fen: "8/8/8/8/8/8/4P3/4K2k w - - 0 1", sideToMove: .white, solution: ["e2e4"])
        let engine = LocalChessEngine()
        XCTAssertFalse(engine.validate(move: ChessMove(uci: "e2e4")!, puzzle: puzzle, solvedMoveCount: 1), "index 1 is out of bounds for a 1-move solution")
    }

    func testEngineValidatesSecondMoveInSequence() {
        let puzzle = Puzzle(
            id: "p2",
            rating: 900,
            fen: "8/8/8/8/8/8/4P3/4K2k w - - 0 1",
            sideToMove: .white,
            solution: ["e2e4", "h1g1", "e1e2"]
        )
        let engine = LocalChessEngine()
        XCTAssertTrue(engine.validate(move: ChessMove(uci: "e1e2")!, puzzle: puzzle, solvedMoveCount: 2))
        XCTAssertFalse(engine.validate(move: ChessMove(uci: "e1e2")!, puzzle: puzzle, solvedMoveCount: 0), "should not match at the wrong index")
    }

    func testBundledPuzzlesAreWellFormed() async throws {
        // This target is hosted by the MorningAlarm app (TEST_HOST/BUNDLE_LOADER), so
        // `Bundle.main` here resolves to the app bundle where puzzles.json actually lives —
        // same default the real BundledPuzzleRepository() uses in the shipping app.
        let repository = BundledPuzzleRepository()
        let puzzles = try await repository.puzzles(minRating: 0, maxRating: 9999, count: 1000)
        XCTAssertGreaterThan(puzzles.count, 0, "the bundled puzzles.json should have loaded")

        for puzzle in puzzles {
            XCTAssertFalse(puzzle.solution.isEmpty, "\(puzzle.id) has an empty solution")
            for uci in puzzle.solution {
                XCTAssertNotNil(ChessMove(uci: uci), "\(puzzle.id) has an unparseable move: \(uci)")
            }
        }
    }
}
