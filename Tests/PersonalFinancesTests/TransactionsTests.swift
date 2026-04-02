import Foundation
import XCTest
@testable import PersonalFinancesApp

final class TransactionsTests: XCTestCase {
    func testAccountBalanceIncludesIncomeExpenseAndTransfer() {
        let a1 = Account(id: UUID(), name: "A", kind: .checking, currencyCode: "USD", openingBalance: 100, institution: nil, notes: nil, archived: false)
        let a2 = Account(id: UUID(), name: "B", kind: .savings, currencyCode: "USD", openingBalance: 0, institution: nil, notes: nil, archived: false)
        
        let tIncome = Transaction(kind: .income, date: Date(), amount: .init(currencyCode: "USD", value: 50), accountId: a1.id, toAccountId: nil, category: nil, customCategoryName: nil, payee: "Paycheck", notes: nil, tags: [], relatedBillId: nil, relatedIncomeId: nil)
        let tExpense = Transaction(kind: .expense, date: Date(), amount: .init(currencyCode: "USD", value: 20), accountId: a1.id, toAccountId: nil, category: .other, customCategoryName: nil, payee: "Food", notes: nil, tags: [], relatedBillId: nil, relatedIncomeId: nil)
        let tTransfer = Transaction(kind: .transfer, date: Date(), amount: .init(currencyCode: "USD", value: 10), accountId: a1.id, toAccountId: a2.id, category: nil, customCategoryName: nil, payee: "Transfer", notes: nil, tags: [], relatedBillId: nil, relatedIncomeId: nil)
        
        let store = AppStore(
            bills: [],
            repository: InMemoryBillRepository(seed: false),
            incomes: [],
            incomeRepository: StubIncomeRepository(),
            accounts: [a1, a2],
            accountRepository: StubAccountRepository(),
            transactions: [tIncome, tExpense, tTransfer],
            transactionRepository: StubTransactionRepository(),
            goals: [],
            goalRepository: StubGoalRepository(),
            debts: [],
            debtRepository: StubDebtRepository()
        )
        
        XCTAssertEqual(store.balance(forAccountId: a1.id), 120)
        XCTAssertEqual(store.balance(forAccountId: a2.id), 10)
        XCTAssertEqual(store.netWorth(in: "USD"), 130)
    }
}

private final class StubIncomeRepository: IncomeRepository {
    func loadIncomes() -> [Income] { [] }
    func save(incomes: [Income]) throws {}
}

private final class StubAccountRepository: AccountRepository {
    func loadAccounts() -> [Account] { [] }
    func save(accounts: [Account]) throws {}
}

private final class StubTransactionRepository: TransactionRepository {
    func loadTransactions() -> [Transaction] { [] }
    func save(transactions: [Transaction]) throws {}
}

private final class StubGoalRepository: GoalRepository {
    func loadGoals() -> [Goal] { [] }
    func save(goals: [Goal]) throws {}
}

private final class StubDebtRepository: DebtRepository {
    func loadDebts() -> [Debt] { [] }
    func save(debts: [Debt]) throws {}
}

