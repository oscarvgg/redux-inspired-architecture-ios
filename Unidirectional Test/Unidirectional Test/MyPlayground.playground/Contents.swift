
import RxSwift
import PlaygroundSupport
/*:
 Let's start by creating the app state
*/
protocol Stateable {}

struct AppState: Stateable {
    
    // user
    let currentUser: String?
    let currentBalance: Float
    
    init(currentUser: String? = nil,
         currentBalance: Float? = nil,
         original: AppState? = nil) {
        self.currentUser = currentUser ?? original?.currentUser ?? nil
        self.currentBalance = currentBalance ?? original?.currentBalance ?? 0
    }
}
/*:
 Abstract use case. Use cases are responsible for updating the state of the app
 */
protocol UseCaseable {
    
    associatedtype T: Stateable
    
    static func execute(state: T,
                        parameters: UseCaseParameter?) throws -> T
}

protocol AsyncUseCaseable {
    
    associatedtype T: Stateable
    
    static func execute(state: T,
                        parameters: UseCaseParameter?) throws -> Observable<T>
}

enum UseCaseError: Error {
    
    case invalidParameters(expected: String?)
    // add any other error cases that can be thrown by a use case
}
/*:
 This are the parameters you send to the use case. Kind of like the actions in Redux
 */
enum UseCaseParameter {
    
    case balance(Float)
    case superAwesomeParameter(String, Int)
}

class StateStore <T:Stateable> {
    
    let state: Variable<T>
    let disposeBag = DisposeBag()
    var currentState: T {
        return state.value
    }
    
    init(initialState: T) {
        state = Variable(initialState)
    }
    
    func updateState(_ newState: T) {
        state.value = newState
    }
    
    func updateState<U: UseCaseable>(_ useCase: U.Type,
                     parameters: UseCaseParameter? = nil) throws where U.T == T {
        let newAppState = try useCase
            .execute(state: currentState,
                     parameters: parameters)
        updateState(newAppState)
    }
    
    func updateState<U: AsyncUseCaseable>(_ useCase: U.Type,
                     parameters: UseCaseParameter? = nil) throws where U.T == T {
        try useCase.execute(state: currentState,
                            parameters: parameters)
            .asObservable()
            .subscribe(
                onNext: { [unowned self] newAppState in
                    self.updateState(newAppState)
                },
                onError: { error in
                    print("#DEBUG: \(error.localizedDescription)")
            })
            .addDisposableTo(disposeBag)
    }
    
}
/*:
 Now we create a global variable to store the app state. This may look like an anti-pattern, but couln't come with a better solution.
 */
let MainStore = StateStore<AppState>(initialState: AppState())
/*:
 Let's create a use case.
 */
struct MainUseCase {
    
    static let disposableBag = DisposeBag()
    
    struct LoadUsername: UseCaseable {
        
        typealias State = AppState
        
        static func execute(state: State,
                            parameters: UseCaseParameter? = nil) throws -> State {
            let originalAppState = MainStore.currentState
            return AppState(currentUser: "Oscar",
                            original: originalAppState)
        }
    }
    
    struct UpdateBalance: AsyncUseCaseable {
        
        static func execute(state: AppState,
                            parameters: UseCaseParameter? = nil) throws -> Observable<AppState> {
            guard let parameters = parameters else {
                throw UseCaseError.invalidParameters(expected: "expected a parameter")
            }
            
            switch parameters {
            case .balance(let newBalance):
                return Observable.create { observer in
                    let originalAppState = MainStore.currentState
                    // Here you should go to a data source to save the balance. For symplicity, I will just update the state
                    let newState = AppState(currentBalance: newBalance,
                                            original: originalAppState)
                    observer.on(.next(newState))
                    return Disposables.create()
                }
            default:
                throw UseCaseError.invalidParameters(expected: "expected a balance value")
            }
        }
    }
    
    struct IncrementBalanceBy100: AsyncUseCaseable {
        
        static func execute(state: AppState,
                            parameters: UseCaseParameter? = nil) throws -> Observable<AppState> {
            return Observable.create { observer in
                let originalAppState = MainStore.currentState
                let newBalance = originalAppState.currentBalance + 100
                let newState = AppState(currentBalance: newBalance,
                                        original: originalAppState)
                observer.on(.next(newState))
                return Disposables.create()
            }
        }
    }
}
/*:
 Now let's create a view
 */
class SimpleView: UIViewController {
    
    let usernameLabel = UILabel()
    let balanceLabel = UILabel()
    let addButton = UIButton()
    let disposableBag = DisposeBag()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        configLayout()
        
        do {
            try MainStore.updateState(MainUseCase.LoadUsername.self)
            // Here I'm going to set the balance to 500
            try MainStore.updateState(MainUseCase.UpdateBalance.self,
                                      parameters: .balance(500))
        }
        catch {
            print("Unhandled error")
        }
        
        MainStore
            .state
            .asObservable()
            .observeOn(MainScheduler.instance)
            .subscribe(onNext: { [unowned self] state in
                // Whenever the state gets updated, we'll get a call to this closure
                self.usernameLabel.text = state.currentUser
                self.balanceLabel.text = String(state.currentBalance)
            })
            .addDisposableTo(disposableBag)
    }
    
    func configLayout() {
        view.frame = CGRect(x: 0, y: 0, width: 250, height: 250)
        view.backgroundColor = #colorLiteral(red: 1, green: 1, blue: 1, alpha: 1)
        view.isUserInteractionEnabled = true
        
        usernameLabel.textColor = #colorLiteral(red: 0, green: 0, blue: 0, alpha: 1)
        usernameLabel.font = UIFont.systemFont(ofSize: 18)
        usernameLabel.backgroundColor = #colorLiteral(red: 0.2588235438, green: 0.7568627596, blue: 0.9686274529, alpha: 1)
        usernameLabel.frame = CGRect(x: 0, y: 0, width: 250, height: 125)
        usernameLabel.textAlignment = NSTextAlignment.center
        
        balanceLabel.textColor = #colorLiteral(red: 0, green: 0, blue: 0, alpha: 1)
        balanceLabel.font = UIFont.systemFont(ofSize: 18)
        balanceLabel.backgroundColor = #colorLiteral(red: 0.5843137503, green: 0.8235294223, blue: 0.4196078479, alpha: 1)
        balanceLabel.frame = CGRect(x: 0, y: 125, width: 250, height: 125)
        balanceLabel.textAlignment = NSTextAlignment.center
        
        addButton.frame = CGRect(x: 0, y: 200, width: 50, height: 50)
        addButton.addTarget(self,
                            action: #selector(didPressIncrementBalance),
                            for: .touchUpInside)
        addButton.setTitle("+", for: .normal)
        addButton.backgroundColor = #colorLiteral(red: 0.9098039269, green: 0.4784313738, blue: 0.6431372762, alpha: 1)
        addButton.isEnabled = true
        addButton.isUserInteractionEnabled = true
        
        view.addSubview(usernameLabel)
        view.addSubview(balanceLabel)
        view.addSubview(addButton)
    }
    
    func didPressIncrementBalance() {
        do {
            try MainStore.updateState(MainUseCase
                .IncrementBalanceBy100
                .self)
        }
        catch {
            print("Unhandled error")
        }
    }
}
/*:
 Finally, lets create an instance of the view controller to test everything out.
 */
let simpleView = SimpleView()
simpleView.view


PlaygroundPage.current.liveView = simpleView.view
/*:
 To try the result of this tutorial, open the asistant editor (View -> Assistant Editor -> Show Assistant Editor)
 */
