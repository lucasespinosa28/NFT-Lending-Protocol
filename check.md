**THIS CHECKLIST IS NOT COMPLETE**. Use `--show-ignored-findings` to show all the results.
Summary
 - [incorrect-exp](#incorrect-exp) (1 results) (High)
 - [unchecked-transfer](#unchecked-transfer) (3 results) (High)
 - [uninitialized-state](#uninitialized-state) (1 results) (High)
 - [divide-before-multiply](#divide-before-multiply) (9 results) (Medium)
 - [reentrancy-no-eth](#reentrancy-no-eth) (5 results) (Medium)
 - [unused-return](#unused-return) (1 results) (Medium)
 - [shadowing-local](#shadowing-local) (10 results) (Low)
 - [missing-zero-check](#missing-zero-check) (6 results) (Low)
 - [reentrancy-benign](#reentrancy-benign) (3 results) (Low)
 - [reentrancy-events](#reentrancy-events) (3 results) (Low)
 - [timestamp](#timestamp) (21 results) (Low)
 - [assembly](#assembly) (20 results) (Informational)
 - [pragma](#pragma) (1 results) (Informational)
 - [costly-loop](#costly-loop) (1 results) (Informational)
 - [dead-code](#dead-code) (27 results) (Informational)
 - [solc-version](#solc-version) (1 results) (Informational)
 - [low-level-calls](#low-level-calls) (1 results) (Informational)
 - [naming-convention](#naming-convention) (5 results) (Informational)
 - [too-many-digits](#too-many-digits) (1 results) (Informational)
 - [unused-state](#unused-state) (1 results) (Informational)
 - [constable-states](#constable-states) (1 results) (Optimization)
 - [var-read-using-this](#var-read-using-this) (7 results) (Optimization)
## incorrect-exp
Impact: High
Confidence: Medium
 - [ ] ID-0
[Math.mulDiv(uint256,uint256,uint256)](lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L204-L275) has bitwise-xor operator ^ instead of the exponentiation operator **: 
	 - [inverse = (3 * denominator) ^ 2](lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L257)

lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L204-L275


## unchecked-transfer
Impact: High
Confidence: Medium
 - [ ] ID-1
[MockRoyaltyModule.fundModule(address,uint256)](src/mocks/MockRoyaltyModule.sol#L25-L27) ignores return value by [IERC20(currencyToken).transferFrom(msg.sender,address(this),amount)](src/mocks/MockRoyaltyModule.sol#L26)

src/mocks/MockRoyaltyModule.sol#L25-L27


 - [ ] ID-2
[MockRoyaltyModule.collectRoyaltyTokens(address,address)](src/mocks/MockRoyaltyModule.sol#L29-L45) ignores return value by [IERC20(token).transfer(msg.sender,collectedAmount)](src/mocks/MockRoyaltyModule.sol#L41)

src/mocks/MockRoyaltyModule.sol#L29-L45


 - [ ] ID-3
[RoyaltyManager.withdrawRoyalty(address,address,address,uint256)](src/core/manager/RoyaltyManager.sol#L80-L98) ignores return value by [IERC20(currencyToken).transfer(recipient,amount)](src/core/manager/RoyaltyManager.sol#L95)

src/core/manager/RoyaltyManager.sol#L80-L98


## uninitialized-state
Impact: High
Confidence: High
 - [ ] ID-4
[MockIPAssetRegistry._ipAccountImpl](src/mocks/MockIPAssetRegistry.sol#L13) is never initialized. It is used in:
	- [MockIPAssetRegistry.getIPAccountImpl()](src/mocks/MockIPAssetRegistry.sol#L38-L40)

src/mocks/MockIPAssetRegistry.sol#L13


## divide-before-multiply
Impact: Medium
Confidence: Medium
 - [ ] ID-5
[Math.mulDiv(uint256,uint256,uint256)](lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L204-L275) performs a multiplication on the result of a division:
	- [denominator = denominator / twos](lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L242)
	- [inverse *= 2 - denominator * inverse](lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L265)

lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L204-L275


 - [ ] ID-6
[Math.mulDiv(uint256,uint256,uint256)](lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L204-L275) performs a multiplication on the result of a division:
	- [denominator = denominator / twos](lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L242)
	- [inverse = (3 * denominator) ^ 2](lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L257)

lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L204-L275


 - [ ] ID-7
[Math.mulDiv(uint256,uint256,uint256)](lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L204-L275) performs a multiplication on the result of a division:
	- [low = low / twos](lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L245)
	- [result = low * inverse](lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L272)

lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L204-L275


 - [ ] ID-8
[Math.invMod(uint256,uint256)](lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L315-L361) performs a multiplication on the result of a division:
	- [quotient = gcd / remainder](lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L337)
	- [(gcd,remainder) = (remainder,gcd - remainder * quotient)](lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L339-L346)

lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L315-L361


 - [ ] ID-9
[Math.mulDiv(uint256,uint256,uint256)](lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L204-L275) performs a multiplication on the result of a division:
	- [denominator = denominator / twos](lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L242)
	- [inverse *= 2 - denominator * inverse](lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L263)

lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L204-L275


 - [ ] ID-10
[Math.mulDiv(uint256,uint256,uint256)](lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L204-L275) performs a multiplication on the result of a division:
	- [denominator = denominator / twos](lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L242)
	- [inverse *= 2 - denominator * inverse](lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L261)

lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L204-L275


 - [ ] ID-11
[Math.mulDiv(uint256,uint256,uint256)](lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L204-L275) performs a multiplication on the result of a division:
	- [denominator = denominator / twos](lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L242)
	- [inverse *= 2 - denominator * inverse](lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L266)

lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L204-L275


 - [ ] ID-12
[Math.mulDiv(uint256,uint256,uint256)](lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L204-L275) performs a multiplication on the result of a division:
	- [denominator = denominator / twos](lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L242)
	- [inverse *= 2 - denominator * inverse](lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L264)

lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L204-L275


 - [ ] ID-13
[Math.mulDiv(uint256,uint256,uint256)](lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L204-L275) performs a multiplication on the result of a division:
	- [denominator = denominator / twos](lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L242)
	- [inverse *= 2 - denominator * inverse](lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L262)

lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L204-L275


## reentrancy-no-eth
Impact: Medium
Confidence: Medium
 - [ ] ID-14
Reentrancy in [MockRoyaltyModule.collectRoyaltyTokens(address,address)](src/mocks/MockRoyaltyModule.sol#L29-L45):
	External calls:
	- [IERC20(token).transfer(msg.sender,collectedAmount)](src/mocks/MockRoyaltyModule.sol#L41)
	State variables written after the call(s):
	- [royaltyAmountsToCollect[ipId][token] = 0](src/mocks/MockRoyaltyModule.sol#L42)
	[MockRoyaltyModule.royaltyAmountsToCollect](src/mocks/MockRoyaltyModule.sol#L11) can be used in cross function reentrancies:
	- [MockRoyaltyModule.collectRoyaltyTokens(address,address)](src/mocks/MockRoyaltyModule.sol#L29-L45)
	- [MockRoyaltyModule.royaltyAmountsToCollect](src/mocks/MockRoyaltyModule.sol#L11)
	- [MockRoyaltyModule.setRoyaltyAmount(address,address,uint256)](src/mocks/MockRoyaltyModule.sol#L19-L21)

src/mocks/MockRoyaltyModule.sol#L29-L45


 - [ ] ID-15
Reentrancy in [LoanManager.claimAndRepay(bytes32)](src/core/lending/LoanManager.sol#L225-L271):
	External calls:
	- [royaltyManager.claimRoyalty(ipIdToUse,loan.currency)](src/core/lending/LoanManager.sol#L240)
	- [royaltyManager.withdrawRoyalty(ipIdToUse,loan.currency,loan.lender,amountToWithdrawFromRoyalty)](src/core/lending/LoanManager.sol#L250)
	State variables written after the call(s):
	- [loan.accruedInterest = interest](src/core/lending/LoanManager.sol#L253)
	[LoanManager.loans](src/core/lending/LoanManager.sol#L27) can be used in cross function reentrancies:
	- [LoanManager.calculateInterest(bytes32)](src/core/lending/LoanManager.sol#L199-L206)
	- [LoanManager.getLoan(bytes32)](src/core/lending/LoanManager.sol#L284-L287)
	- [LoanManager.isLoanInDefault(bytes32)](src/core/lending/LoanManager.sol#L295-L299)
	- [LoanManager.isLoanRepayable(bytes32)](src/core/lending/LoanManager.sol#L289-L293)
	- [LoanManager.loans](src/core/lending/LoanManager.sol#L27)
	- [loan.status = ILendingProtocol.LoanStatus.REPAID](src/core/lending/LoanManager.sol#L254)
	[LoanManager.loans](src/core/lending/LoanManager.sol#L27) can be used in cross function reentrancies:
	- [LoanManager.calculateInterest(bytes32)](src/core/lending/LoanManager.sol#L199-L206)
	- [LoanManager.getLoan(bytes32)](src/core/lending/LoanManager.sol#L284-L287)
	- [LoanManager.isLoanInDefault(bytes32)](src/core/lending/LoanManager.sol#L295-L299)
	- [LoanManager.isLoanRepayable(bytes32)](src/core/lending/LoanManager.sol#L289-L293)
	- [LoanManager.loans](src/core/lending/LoanManager.sol#L27)
	- [loan.principalAmount = originalPrincipal - amountToWithdrawFromRoyalty](src/core/lending/LoanManager.sol#L257)
	[LoanManager.loans](src/core/lending/LoanManager.sol#L27) can be used in cross function reentrancies:
	- [LoanManager.calculateInterest(bytes32)](src/core/lending/LoanManager.sol#L199-L206)
	- [LoanManager.getLoan(bytes32)](src/core/lending/LoanManager.sol#L284-L287)
	- [LoanManager.isLoanInDefault(bytes32)](src/core/lending/LoanManager.sol#L295-L299)
	- [LoanManager.isLoanRepayable(bytes32)](src/core/lending/LoanManager.sol#L289-L293)
	- [LoanManager.loans](src/core/lending/LoanManager.sol#L27)
	- [loan.accruedInterest = interest](src/core/lending/LoanManager.sol#L260)
	[LoanManager.loans](src/core/lending/LoanManager.sol#L27) can be used in cross function reentrancies:
	- [LoanManager.calculateInterest(bytes32)](src/core/lending/LoanManager.sol#L199-L206)
	- [LoanManager.getLoan(bytes32)](src/core/lending/LoanManager.sol#L284-L287)
	- [LoanManager.isLoanInDefault(bytes32)](src/core/lending/LoanManager.sol#L295-L299)
	- [LoanManager.isLoanRepayable(bytes32)](src/core/lending/LoanManager.sol#L289-L293)
	- [LoanManager.loans](src/core/lending/LoanManager.sol#L27)
	- [loan.status = ILendingProtocol.LoanStatus.REPAID](src/core/lending/LoanManager.sol#L261)
	[LoanManager.loans](src/core/lending/LoanManager.sol#L27) can be used in cross function reentrancies:
	- [LoanManager.calculateInterest(bytes32)](src/core/lending/LoanManager.sol#L199-L206)
	- [LoanManager.getLoan(bytes32)](src/core/lending/LoanManager.sol#L284-L287)
	- [LoanManager.isLoanInDefault(bytes32)](src/core/lending/LoanManager.sol#L295-L299)
	- [LoanManager.isLoanRepayable(bytes32)](src/core/lending/LoanManager.sol#L289-L293)
	- [LoanManager.loans](src/core/lending/LoanManager.sol#L27)

src/core/lending/LoanManager.sol#L225-L271


 - [ ] ID-16
Reentrancy in [LoanManager.claimAndRepay(bytes32)](src/core/lending/LoanManager.sol#L225-L271):
	External calls:
	- [royaltyManager.claimRoyalty(ipIdToUse,loan.currency)](src/core/lending/LoanManager.sol#L240)
	State variables written after the call(s):
	- [loan.accruedInterest = interest](src/core/lending/LoanManager.sol#L266)
	[LoanManager.loans](src/core/lending/LoanManager.sol#L27) can be used in cross function reentrancies:
	- [LoanManager.calculateInterest(bytes32)](src/core/lending/LoanManager.sol#L199-L206)
	- [LoanManager.getLoan(bytes32)](src/core/lending/LoanManager.sol#L284-L287)
	- [LoanManager.isLoanInDefault(bytes32)](src/core/lending/LoanManager.sol#L295-L299)
	- [LoanManager.isLoanRepayable(bytes32)](src/core/lending/LoanManager.sol#L289-L293)
	- [LoanManager.loans](src/core/lending/LoanManager.sol#L27)
	- [loan.status = ILendingProtocol.LoanStatus.REPAID](src/core/lending/LoanManager.sol#L267)
	[LoanManager.loans](src/core/lending/LoanManager.sol#L27) can be used in cross function reentrancies:
	- [LoanManager.calculateInterest(bytes32)](src/core/lending/LoanManager.sol#L199-L206)
	- [LoanManager.getLoan(bytes32)](src/core/lending/LoanManager.sol#L284-L287)
	- [LoanManager.isLoanInDefault(bytes32)](src/core/lending/LoanManager.sol#L295-L299)
	- [LoanManager.isLoanRepayable(bytes32)](src/core/lending/LoanManager.sol#L289-L293)
	- [LoanManager.loans](src/core/lending/LoanManager.sol#L27)

src/core/lending/LoanManager.sol#L225-L271


 - [ ] ID-17
Reentrancy in [LoanManager.buyCollateralAndRepay(bytes32,uint256)](src/core/lending/LoanManager.sol#L322-L341):
	External calls:
	- [IERC721(loan.nftContract).safeTransferFrom(address(this),msg.sender,loan.nftTokenId)](src/core/lending/LoanManager.sol#L334)
	State variables written after the call(s):
	- [loan.status = ILendingProtocol.LoanStatus.REPAID](src/core/lending/LoanManager.sol#L336)
	[LoanManager.loans](src/core/lending/LoanManager.sol#L27) can be used in cross function reentrancies:
	- [LoanManager.calculateInterest(bytes32)](src/core/lending/LoanManager.sol#L199-L206)
	- [LoanManager.getLoan(bytes32)](src/core/lending/LoanManager.sol#L284-L287)
	- [LoanManager.isLoanInDefault(bytes32)](src/core/lending/LoanManager.sol#L295-L299)
	- [LoanManager.isLoanRepayable(bytes32)](src/core/lending/LoanManager.sol#L289-L293)
	- [LoanManager.loans](src/core/lending/LoanManager.sol#L27)
	- [loan.accruedInterest = interest](src/core/lending/LoanManager.sol#L337)
	[LoanManager.loans](src/core/lending/LoanManager.sol#L27) can be used in cross function reentrancies:
	- [LoanManager.calculateInterest(bytes32)](src/core/lending/LoanManager.sol#L199-L206)
	- [LoanManager.getLoan(bytes32)](src/core/lending/LoanManager.sol#L284-L287)
	- [LoanManager.isLoanInDefault(bytes32)](src/core/lending/LoanManager.sol#L295-L299)
	- [LoanManager.isLoanRepayable(bytes32)](src/core/lending/LoanManager.sol#L289-L293)
	- [LoanManager.loans](src/core/lending/LoanManager.sol#L27)

src/core/lending/LoanManager.sol#L322-L341


 - [ ] ID-18
Reentrancy in [LoanManager.repayLoan(bytes32)](src/core/lending/LoanManager.sol#L208-L223):
	External calls:
	- [IERC721(loan.nftContract).safeTransferFrom(address(this),loan.borrower,loan.nftTokenId)](src/core/lending/LoanManager.sol#L218)
	State variables written after the call(s):
	- [loan.status = ILendingProtocol.LoanStatus.REPAID](src/core/lending/LoanManager.sol#L220)
	[LoanManager.loans](src/core/lending/LoanManager.sol#L27) can be used in cross function reentrancies:
	- [LoanManager.calculateInterest(bytes32)](src/core/lending/LoanManager.sol#L199-L206)
	- [LoanManager.getLoan(bytes32)](src/core/lending/LoanManager.sol#L284-L287)
	- [LoanManager.isLoanInDefault(bytes32)](src/core/lending/LoanManager.sol#L295-L299)
	- [LoanManager.isLoanRepayable(bytes32)](src/core/lending/LoanManager.sol#L289-L293)
	- [LoanManager.loans](src/core/lending/LoanManager.sol#L27)
	- [loan.accruedInterest = interest](src/core/lending/LoanManager.sol#L221)
	[LoanManager.loans](src/core/lending/LoanManager.sol#L27) can be used in cross function reentrancies:
	- [LoanManager.calculateInterest(bytes32)](src/core/lending/LoanManager.sol#L199-L206)
	- [LoanManager.getLoan(bytes32)](src/core/lending/LoanManager.sol#L284-L287)
	- [LoanManager.isLoanInDefault(bytes32)](src/core/lending/LoanManager.sol#L295-L299)
	- [LoanManager.isLoanRepayable(bytes32)](src/core/lending/LoanManager.sol#L289-L293)
	- [LoanManager.loans](src/core/lending/LoanManager.sol#L27)

src/core/lending/LoanManager.sol#L208-L223


## unused-return
Impact: Medium
Confidence: Medium
 - [ ] ID-19
[LoanManager.listCollateralForSale(bytes32,uint256)](src/core/lending/LoanManager.sol#L301-L313) ignores return value by [purchaseBundler.listCollateralForSale(loanId,loan.nftContract,loan.nftTokenId,loan.isVault,price,loan.currency,loan.borrower)](src/core/lending/LoanManager.sol#L309-L311)

src/core/lending/LoanManager.sol#L301-L313


## shadowing-local
Impact: Low
Confidence: High
 - [ ] ID-20
[Stash.constructor(string,string,address,address).name](src/core/Stash.sol#L47) shadows:
	- [ERC721.name()](lib/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol#L74-L76) (function)
	- [IERC721Metadata.name()](lib/openzeppelin-contracts/contracts/token/ERC721/extensions/IERC721Metadata.sol#L16) (function)

src/core/Stash.sol#L47


 - [ ] ID-21
[ERC20Mock.constructor(string,string).symbol](src/mocks/ERC20Mock.sol#L19) shadows:
	- [ERC20.symbol()](lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol#L60-L62) (function)
	- [IERC20Metadata.symbol()](lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol#L20) (function)

src/mocks/ERC20Mock.sol#L19


 - [ ] ID-22
[Stash.constructor(string,string,address,address).symbol](src/core/Stash.sol#L48) shadows:
	- [ERC721.symbol()](lib/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol#L81-L83) (function)
	- [IERC721Metadata.symbol()](lib/openzeppelin-contracts/contracts/token/ERC721/extensions/IERC721Metadata.sol#L21) (function)

src/core/Stash.sol#L48


 - [ ] ID-23
[CollectionManager.constructor(address,address[]).owner](src/core/manager/CollectionManager.sol#L19) shadows:
	- [Ownable.owner()](lib/openzeppelin-contracts/contracts/access/Ownable.sol#L56-L58) (function)

src/core/manager/CollectionManager.sol#L19


 - [ ] ID-24
[ERC20Mock.constructor(string,string).name](src/mocks/ERC20Mock.sol#L19) shadows:
	- [ERC20.name()](lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol#L52-L54) (function)
	- [IERC20Metadata.name()](lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol#L15) (function)

src/mocks/ERC20Mock.sol#L19


 - [ ] ID-25
[ERC721Mock.constructor(string,string).symbol](src/mocks/ERC721Mock.sol#L19) shadows:
	- [ERC721.symbol()](lib/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol#L81-L83) (function)
	- [IERC721Metadata.symbol()](lib/openzeppelin-contracts/contracts/token/ERC721/extensions/IERC721Metadata.sol#L21) (function)

src/mocks/ERC721Mock.sol#L19


 - [ ] ID-26
[IRoyaltyModule.setRoyaltyFeePercent(uint32).royaltyFeePercent](lib/protocol-core-v1/contracts/interfaces/modules/royalty/IRoyaltyModule.sol#L98) shadows:
	- [IRoyaltyModule.royaltyFeePercent()](lib/protocol-core-v1/contracts/interfaces/modules/royalty/IRoyaltyModule.sol#L176) (function)

lib/protocol-core-v1/contracts/interfaces/modules/royalty/IRoyaltyModule.sol#L98


 - [ ] ID-27
[ERC721Mock.constructor(string,string).name](src/mocks/ERC721Mock.sol#L19) shadows:
	- [ERC721.name()](lib/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol#L74-L76) (function)
	- [IERC721Metadata.name()](lib/openzeppelin-contracts/contracts/token/ERC721/extensions/IERC721Metadata.sol#L16) (function)

src/mocks/ERC721Mock.sol#L19


 - [ ] ID-28
[IRoyaltyModule.setTreasury(address).treasury](lib/protocol-core-v1/contracts/interfaces/modules/royalty/IRoyaltyModule.sol#L93) shadows:
	- [IRoyaltyModule.treasury()](lib/protocol-core-v1/contracts/interfaces/modules/royalty/IRoyaltyModule.sol#L173) (function)

lib/protocol-core-v1/contracts/interfaces/modules/royalty/IRoyaltyModule.sol#L93


 - [ ] ID-29
[Stash.getOriginalTokenInfo(uint256).owner](src/core/Stash.sol#L144) shadows:
	- [Ownable.owner()](lib/openzeppelin-contracts/contracts/access/Ownable.sol#L56-L58) (function)

src/core/Stash.sol#L144


## missing-zero-check
Impact: Low
Confidence: Medium
 - [ ] ID-30
[MockIPAssetRegistry.setRegistrationFee(address,address,uint96).treasury](src/mocks/MockIPAssetRegistry.sol#L20) lacks a zero-check on :
		- [_treasury = treasury](src/mocks/MockIPAssetRegistry.sol#L21)

src/mocks/MockIPAssetRegistry.sol#L20


 - [ ] ID-31
[MockRoyaltyModule.collectRoyaltyTokens(address,address).ipId](src/mocks/MockRoyaltyModule.sol#L29) lacks a zero-check on :
		- [lastIpIdCollected = ipId](src/mocks/MockRoyaltyModule.sol#L31)

src/mocks/MockRoyaltyModule.sol#L29


 - [ ] ID-32
[Stash.constructor(string,string,address,address)._specificOriginalContract](src/core/Stash.sol#L49) lacks a zero-check on :
		- [specificOriginalContract = _specificOriginalContract](src/core/Stash.sol#L53)

src/core/Stash.sol#L49


 - [ ] ID-33
[MockIPAssetRegistry.setRegistrationFee(address,address,uint96).feeToken](src/mocks/MockIPAssetRegistry.sol#L20) lacks a zero-check on :
		- [_feeToken = feeToken](src/mocks/MockIPAssetRegistry.sol#L22)

src/mocks/MockIPAssetRegistry.sol#L20


 - [ ] ID-34
[MockRoyaltyModule.collectRoyaltyTokens(address,address).token](src/mocks/MockRoyaltyModule.sol#L29) lacks a zero-check on :
		- [lastCurrencyTokenCollected = token](src/mocks/MockRoyaltyModule.sol#L32)

src/mocks/MockRoyaltyModule.sol#L29


 - [ ] ID-35
[AdminManager.emergencyWithdrawNative(address,uint256).to](src/core/lending/AdminManager.sol#L140) lacks a zero-check on :
		- [(success,None) = to.call{value: amount}()](src/core/lending/AdminManager.sol#L141)

src/core/lending/AdminManager.sol#L140


## reentrancy-benign
Impact: Low
Confidence: Medium
 - [ ] ID-36
Reentrancy in [ERC721Mock.mint(address,uint256)](src/mocks/ERC721Mock.sol#L40-L45):
	External calls:
	- [_safeMint(to,tokenId)](src/mocks/ERC721Mock.sol#L41)
		- [ERC721Utils.checkOnERC721Received(_msgSender(),address(0),to,tokenId,data)](lib/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol#L315)
		- [retval = IERC721Receiver(to).onERC721Received(operator,from,tokenId,data)](lib/openzeppelin-contracts/contracts/token/ERC721/utils/ERC721Utils.sol#L33-L47)
	State variables written after the call(s):
	- [_nextTokenId = tokenId + 1](src/mocks/ERC721Mock.sol#L43)

src/mocks/ERC721Mock.sol#L40-L45


 - [ ] ID-37
Reentrancy in [LoanManager.acceptLoanRequest(bytes32)](src/core/lending/LoanManager.sol#L371-L453):
	External calls:
	- [IERC721(request.nftContract).safeTransferFrom(request.borrower,address(this),request.nftTokenId)](src/core/lending/LoanManager.sol#L395)
	State variables written after the call(s):
	- [loanCounter = _incrementLoanCounter()](src/core/lending/LoanManager.sol#L398)
		- [loanCounter ++](src/core/lending/LoanManager.sol#L462)
	- [loans[loanId] = ILendingProtocol.Loan({loanId:loanId,offerId:requestId,borrower:request.borrower,lender:msg.sender,nftContract:request.nftContract,nftTokenId:request.nftTokenId,isVault:false,currency:request.currency,principalAmount:request.principalAmount,interestRateAPR:request.interestRateAPR,originationFeePaid:originationFee,startTime:startTime,dueTime:dueTime,accruedInterest:0,status:ILendingProtocol.LoanStatus.ACTIVE,storyIpId:address(0),isStoryAsset:false})](src/core/lending/LoanManager.sol#L406-L424)

src/core/lending/LoanManager.sol#L371-L453


 - [ ] ID-38
Reentrancy in [LoanManager.acceptLoanOffer(bytes32,address,uint256)](src/core/lending/LoanManager.sol#L105-L197):
	External calls:
	- [IERC721(effectiveCollateralContract).safeTransferFrom(msg.sender,address(this),effectiveCollateralTokenId)](src/core/lending/LoanManager.sol#L150)
	State variables written after the call(s):
	- [loanCounter ++](src/core/lending/LoanManager.sol#L152)
	- [loans[loanId] = ILendingProtocol.Loan({loanId:loanId,offerId:offerId,borrower:msg.sender,lender:offer.lender,nftContract:effectiveCollateralContract,nftTokenId:effectiveCollateralTokenId,isVault:false,currency:offer.currency,principalAmount:offer.principalAmount,interestRateAPR:offer.interestRateAPR,originationFeePaid:originationFee,startTime:startTime,dueTime:dueTime,accruedInterest:0,status:ILendingProtocol.LoanStatus.ACTIVE,storyIpId:loanStoryIpId,isStoryAsset:loanIsStoryAsset})](src/core/lending/LoanManager.sol#L158-L176)

src/core/lending/LoanManager.sol#L105-L197


## reentrancy-events
Impact: Low
Confidence: Medium
 - [ ] ID-39
Reentrancy in [LendingProtocol.acceptLoanRequest(bytes32)](src/core/LendingProtocol.sol#L363-L393):
	External calls:
	- [loanId = super.acceptLoanRequest(requestId)](src/core/LendingProtocol.sol#L377)
		- [IERC721(request.nftContract).safeTransferFrom(request.borrower,address(this),request.nftTokenId)](src/core/lending/LoanManager.sol#L395)
	Event emitted after the call(s):
	- [LoanRequestAccepted(requestId,loanId,msg.sender,request.borrower,request.nftContract,request.nftTokenId,request.currency,request.principalAmount,loans[loanId].dueTime)](src/core/LendingProtocol.sol#L381-L391)

src/core/LendingProtocol.sol#L363-L393


 - [ ] ID-40
Reentrancy in [Stash.unstash(uint256)](src/core/Stash.sol#L111-L135):
	External calls:
	- [IERC721(originalContract).safeTransferFrom(address(this),msg.sender,originalTokenId)](src/core/Stash.sol#L132)
	Event emitted after the call(s):
	- [TokenUnstashed(stashTokenId,originalContract,originalTokenId,msg.sender)](src/core/Stash.sol#L134)

src/core/Stash.sol#L111-L135


 - [ ] ID-41
Reentrancy in [Stash.stash(address,uint256)](src/core/Stash.sol#L69-L106):
	External calls:
	- [IERC721(originalContract).safeTransferFrom(msg.sender,address(this),originalTokenId)](src/core/Stash.sol#L102)
	Event emitted after the call(s):
	- [TokenStashed(originalContract,originalTokenId,msg.sender,stashTokenId)](src/core/Stash.sol#L104)

src/core/Stash.sol#L69-L106


## timestamp
Impact: Low
Confidence: Medium
 - [ ] ID-42
[RequestManager.cancelLoanRequest(bytes32)](src/core/lending/RequestManager.sol#L83-L92) uses timestamp for comparisons
	Dangerous comparisons:
	- [require(bool,string)(request.borrower == msg.sender,RM: Not request owner)](src/core/lending/RequestManager.sol#L85)
	- [require(bool,string)(request.isActive,RM: Request not active)](src/core/lending/RequestManager.sol#L86)

src/core/lending/RequestManager.sol#L83-L92


 - [ ] ID-43
[RequestManager.makeLoanRequest(ILendingProtocol.LoanRequestParams)](src/core/lending/RequestManager.sol#L34-L77) uses timestamp for comparisons
	Dangerous comparisons:
	- [require(bool,string)(params.expirationTimestamp > block.timestamp,RM: Expiration in past)](src/core/lending/RequestManager.sol#L52)

src/core/lending/RequestManager.sol#L34-L77


 - [ ] ID-44
[OfferManager._setLoanOfferInactive(bytes32)](src/core/lending/OfferManager.sol#L143-L150) uses timestamp for comparisons
	Dangerous comparisons:
	- [require(bool,string)(offer.isActive,OfferManager: Offer already inactive or does not exist)](src/core/lending/OfferManager.sol#L148)

src/core/lending/OfferManager.sol#L143-L150


 - [ ] ID-45
[LoanManager.isLoanRepayable(bytes32)](src/core/lending/LoanManager.sol#L289-L293) uses timestamp for comparisons
	Dangerous comparisons:
	- [loan.status == ILendingProtocol.LoanStatus.ACTIVE && block.timestamp <= loan.dueTime](src/core/lending/LoanManager.sol#L292)

src/core/lending/LoanManager.sol#L289-L293


 - [ ] ID-46
[LoanManager.repayLoan(bytes32)](src/core/lending/LoanManager.sol#L208-L223) uses timestamp for comparisons
	Dangerous comparisons:
	- [require(bool,string)(loan.status == ILendingProtocol.LoanStatus.ACTIVE,Loan not active)](src/core/lending/LoanManager.sol#L211)
	- [require(bool,string)(block.timestamp <= loan.dueTime,Loan past due (defaulted))](src/core/lending/LoanManager.sol#L212)

src/core/lending/LoanManager.sol#L208-L223


 - [ ] ID-47
[LoanManager.cancelCollateralSale(bytes32)](src/core/lending/LoanManager.sol#L315-L320) uses timestamp for comparisons
	Dangerous comparisons:
	- [require(bool,string)(loan.status == ILendingProtocol.LoanStatus.ACTIVE,Loan not active for sale cancellation)](src/core/lending/LoanManager.sol#L318)

src/core/lending/LoanManager.sol#L315-L320


 - [ ] ID-48
[OfferManager.cancelLoanOffer(bytes32)](src/core/lending/OfferManager.sol#L115-L124) uses timestamp for comparisons
	Dangerous comparisons:
	- [require(bool,string)(offer.lender == msg.sender,Not offer owner)](src/core/lending/OfferManager.sol#L118)
	- [require(bool,string)(offer.isActive,Offer not active)](src/core/lending/OfferManager.sol#L119)

src/core/lending/OfferManager.sol#L115-L124


 - [ ] ID-49
[OfferManager.makeLoanOffer(ILendingProtocol.OfferParams)](src/core/lending/OfferManager.sol#L46-L109) uses timestamp for comparisons
	Dangerous comparisons:
	- [require(bool,string)(params.expirationTimestamp > block.timestamp,Expiration in past)](src/core/lending/OfferManager.sol#L59)

src/core/lending/OfferManager.sol#L46-L109


 - [ ] ID-50
[LoanManager.acceptLoanRequest(bytes32)](src/core/lending/LoanManager.sol#L371-L453) uses timestamp for comparisons
	Dangerous comparisons:
	- [require(bool,string)(request.expirationTimestamp > block.timestamp,LM: Loan request expired)](src/core/lending/LoanManager.sol#L375)

src/core/lending/LoanManager.sol#L371-L453


 - [ ] ID-51
[LoanManager.claimCollateral(bytes32)](src/core/lending/LoanManager.sol#L273-L282) uses timestamp for comparisons
	Dangerous comparisons:
	- [require(bool,string)(loan.status == ILendingProtocol.LoanStatus.ACTIVE,Loan not active)](src/core/lending/LoanManager.sol#L276)
	- [require(bool,string)(block.timestamp > loan.dueTime,Loan not defaulted)](src/core/lending/LoanManager.sol#L277)

src/core/lending/LoanManager.sol#L273-L282


 - [ ] ID-52
[LoanManager._setLoanStatus(bytes32,ILendingProtocol.LoanStatus)](src/core/lending/LoanManager.sol#L455-L459) uses timestamp for comparisons
	Dangerous comparisons:
	- [require(bool,string)(loan.borrower != address(0),LoanManager: Loan does not exist)](src/core/lending/LoanManager.sol#L457)

src/core/lending/LoanManager.sol#L455-L459


 - [ ] ID-53
[LoanManager._updateLoanAfterRenegotiation(bytes32,uint256,uint256,uint64)](src/core/lending/LoanManager.sol#L472-L483) uses timestamp for comparisons
	Dangerous comparisons:
	- [require(bool,string)(loan.borrower != address(0),LoanManager: Loan does not exist for renegotiation)](src/core/lending/LoanManager.sol#L477)
	- [require(bool,string)(loan.status == ILendingProtocol.LoanStatus.ACTIVE,LoanManager: Loan not active for renegotiation)](src/core/lending/LoanManager.sol#L478)

src/core/lending/LoanManager.sol#L472-L483


 - [ ] ID-54
[LoanManager.recordLoanRepaymentViaSale(bytes32,uint256,uint256)](src/core/lending/LoanManager.sol#L343-L359) uses timestamp for comparisons
	Dangerous comparisons:
	- [require(bool,string)(loan.status == ILendingProtocol.LoanStatus.ACTIVE,LM: Loan not active for repayment via sale)](src/core/lending/LoanManager.sol#L352)
	- [require(bool,string)(principalRepaid == loan.principalAmount,LM: Principal mismatch in sale settlement)](src/core/lending/LoanManager.sol#L353)

src/core/lending/LoanManager.sol#L343-L359


 - [ ] ID-55
[LoanManager.isLoanInDefault(bytes32)](src/core/lending/LoanManager.sol#L295-L299) uses timestamp for comparisons
	Dangerous comparisons:
	- [loan.status == ILendingProtocol.LoanStatus.ACTIVE && block.timestamp > loan.dueTime](src/core/lending/LoanManager.sol#L298)

src/core/lending/LoanManager.sol#L295-L299


 - [ ] ID-56
[LoanManager._addLoan(bytes32,ILendingProtocol.Loan)](src/core/lending/LoanManager.sol#L466-L470) uses timestamp for comparisons
	Dangerous comparisons:
	- [require(bool,string)(loans[loanId].borrower == address(0),LoanManager: Loan ID already exists)](src/core/lending/LoanManager.sol#L468)

src/core/lending/LoanManager.sol#L466-L470


 - [ ] ID-57
[LoanManager.claimAndRepay(bytes32)](src/core/lending/LoanManager.sol#L225-L271) uses timestamp for comparisons
	Dangerous comparisons:
	- [require(bool,string)(loan.status == ILendingProtocol.LoanStatus.ACTIVE,Loan not active)](src/core/lending/LoanManager.sol#L228)
	- [require(bool,string)(loan.storyIpId != address(0),Loan is Story asset but IP ID is missing)](src/core/lending/LoanManager.sol#L237)

src/core/lending/LoanManager.sol#L225-L271


 - [ ] ID-58
[LoanManager.listCollateralForSale(bytes32,uint256)](src/core/lending/LoanManager.sol#L301-L313) uses timestamp for comparisons
	Dangerous comparisons:
	- [require(bool,string)(loan.status == ILendingProtocol.LoanStatus.ACTIVE,Loan not active)](src/core/lending/LoanManager.sol#L304)

src/core/lending/LoanManager.sol#L301-L313


 - [ ] ID-59
[LoanManager.acceptLoanOffer(bytes32,address,uint256)](src/core/lending/LoanManager.sol#L105-L197) uses timestamp for comparisons
	Dangerous comparisons:
	- [require(bool,string)(offer.expirationTimestamp > block.timestamp,Offer expired)](src/core/lending/LoanManager.sol#L113)

src/core/lending/LoanManager.sol#L105-L197


 - [ ] ID-60
[LoanManager.buyCollateralAndRepay(bytes32,uint256)](src/core/lending/LoanManager.sol#L322-L341) uses timestamp for comparisons
	Dangerous comparisons:
	- [require(bool,string)(loan.status == ILendingProtocol.LoanStatus.ACTIVE,Loan not active)](src/core/lending/LoanManager.sol#L325)

src/core/lending/LoanManager.sol#L322-L341


 - [ ] ID-61
[RequestManager._setLoanRequestInactive(bytes32)](src/core/lending/RequestManager.sol#L108-L112) uses timestamp for comparisons
	Dangerous comparisons:
	- [require(bool,string)(request.isActive,RM: Request already inactive or does not exist)](src/core/lending/RequestManager.sol#L110)

src/core/lending/RequestManager.sol#L108-L112


 - [ ] ID-62
[LoanManager.calculateInterest(bytes32)](src/core/lending/LoanManager.sol#L199-L206) uses timestamp for comparisons
	Dangerous comparisons:
	- [require(bool,string)(loan.status == ILendingProtocol.LoanStatus.ACTIVE,Loan not active)](src/core/lending/LoanManager.sol#L202)
	- [block.timestamp < loan.dueTime](src/core/lending/LoanManager.sol#L203-L204)

src/core/lending/LoanManager.sol#L199-L206


## assembly
Impact: Informational
Confidence: High
 - [ ] ID-63
[Math.tryMul(uint256,uint256)](lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L73-L84) uses assembly
	- [INLINE ASM](lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L76-L80)

lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L73-L84


 - [ ] ID-64
[Math.mul512(uint256,uint256)](lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L37-L46) uses assembly
	- [INLINE ASM](lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L41-L45)

lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L37-L46


 - [ ] ID-65
[Math.add512(uint256,uint256)](lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L25-L30) uses assembly
	- [INLINE ASM](lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L26-L29)

lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L25-L30


 - [ ] ID-66
[SafeCast.toUint(bool)](lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol#L1157-L1161) uses assembly
	- [INLINE ASM](lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol#L1158-L1160)

lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol#L1157-L1161


 - [ ] ID-67
[Strings._unsafeReadBytesOffset(bytes,uint256)](lib/openzeppelin-contracts/contracts/utils/Strings.sol#L484-L489) uses assembly
	- [INLINE ASM](lib/openzeppelin-contracts/contracts/utils/Strings.sol#L486-L488)

lib/openzeppelin-contracts/contracts/utils/Strings.sol#L484-L489


 - [ ] ID-68
[SafeERC20._callOptionalReturn(IERC20,bytes)](lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol#L173-L191) uses assembly
	- [INLINE ASM](lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol#L176-L186)

lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol#L173-L191


 - [ ] ID-69
[CurrencyManager._addSupportedCurrency(address)](src/core/manager/CurrencyManager.sol#L48-L68) uses assembly
	- [INLINE ASM](src/core/manager/CurrencyManager.sol#L53-L55)

src/core/manager/CurrencyManager.sol#L48-L68


 - [ ] ID-70
[Math.log2(uint256)](lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L612-L651) uses assembly
	- [INLINE ASM](lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L648-L650)

lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L612-L651


 - [ ] ID-71
[Math.mulDiv(uint256,uint256,uint256)](lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L204-L275) uses assembly
	- [INLINE ASM](lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L227-L234)
	- [INLINE ASM](lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L240-L249)

lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L204-L275


 - [ ] ID-72
[Panic.panic(uint256)](lib/openzeppelin-contracts/contracts/utils/Panic.sol#L50-L56) uses assembly
	- [INLINE ASM](lib/openzeppelin-contracts/contracts/utils/Panic.sol#L51-L55)

lib/openzeppelin-contracts/contracts/utils/Panic.sol#L50-L56


 - [ ] ID-73
[Strings.escapeJSON(string)](lib/openzeppelin-contracts/contracts/utils/Strings.sol#L446-L476) uses assembly
	- [INLINE ASM](lib/openzeppelin-contracts/contracts/utils/Strings.sol#L470-L473)

lib/openzeppelin-contracts/contracts/utils/Strings.sol#L446-L476


 - [ ] ID-74
[Math.tryMod(uint256,uint256)](lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L102-L110) uses assembly
	- [INLINE ASM](lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L105-L108)

lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L102-L110


 - [ ] ID-75
[Strings.toString(uint256)](lib/openzeppelin-contracts/contracts/utils/Strings.sol#L45-L63) uses assembly
	- [INLINE ASM](lib/openzeppelin-contracts/contracts/utils/Strings.sol#L50-L52)
	- [INLINE ASM](lib/openzeppelin-contracts/contracts/utils/Strings.sol#L55-L57)

lib/openzeppelin-contracts/contracts/utils/Strings.sol#L45-L63


 - [ ] ID-76
[Math.tryDiv(uint256,uint256)](lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L89-L97) uses assembly
	- [INLINE ASM](lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L92-L95)

lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L89-L97


 - [ ] ID-77
[Strings.toChecksumHexString(address)](lib/openzeppelin-contracts/contracts/utils/Strings.sol#L111-L129) uses assembly
	- [INLINE ASM](lib/openzeppelin-contracts/contracts/utils/Strings.sol#L116-L118)

lib/openzeppelin-contracts/contracts/utils/Strings.sol#L111-L129


 - [ ] ID-78
[ERC721Utils.checkOnERC721Received(address,address,address,uint256,bytes)](lib/openzeppelin-contracts/contracts/token/ERC721/utils/ERC721Utils.sol#L25-L49) uses assembly
	- [INLINE ASM](lib/openzeppelin-contracts/contracts/token/ERC721/utils/ERC721Utils.sol#L43-L45)

lib/openzeppelin-contracts/contracts/token/ERC721/utils/ERC721Utils.sol#L25-L49


 - [ ] ID-79
[Math.tryModExp(uint256,uint256,uint256)](lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L409-L433) uses assembly
	- [INLINE ASM](lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L411-L432)

lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L409-L433


 - [ ] ID-80
[CollectionManager._addWhitelistedCollection(address)](src/core/manager/CollectionManager.sol#L33-L53) uses assembly
	- [INLINE ASM](src/core/manager/CollectionManager.sol#L38-L40)

src/core/manager/CollectionManager.sol#L33-L53


 - [ ] ID-81
[SafeERC20._callOptionalReturnBool(IERC20,bytes)](lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol#L201-L211) uses assembly
	- [INLINE ASM](lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol#L205-L209)

lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol#L201-L211


 - [ ] ID-82
[Math.tryModExp(bytes,bytes,bytes)](lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L449-L471) uses assembly
	- [INLINE ASM](lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L461-L470)

lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L449-L471


## pragma
Impact: Informational
Confidence: High
 - [ ] ID-83
2 different versions of Solidity are used:
	- Version constraint ^0.8.20 is used by:
		-[^0.8.20](lib/openzeppelin-contracts/contracts/access/Ownable.sol#L4)
		-[^0.8.20](lib/openzeppelin-contracts/contracts/interfaces/IERC1363.sol#L4)
		-[^0.8.20](lib/openzeppelin-contracts/contracts/interfaces/IERC165.sol#L4)
		-[^0.8.20](lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol#L4)
		-[^0.8.20](lib/openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol#L3)
		-[^0.8.20](lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol#L4)
		-[^0.8.20](lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol#L4)
		-[^0.8.20](lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol#L4)
		-[^0.8.20](lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol#L4)
		-[^0.8.20](lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol#L4)
		-[^0.8.20](lib/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol#L4)
		-[^0.8.20](lib/openzeppelin-contracts/contracts/token/ERC721/IERC721.sol#L4)
		-[^0.8.20](lib/openzeppelin-contracts/contracts/token/ERC721/IERC721Receiver.sol#L4)
		-[^0.8.20](lib/openzeppelin-contracts/contracts/token/ERC721/extensions/ERC721Burnable.sol#L4)
		-[^0.8.20](lib/openzeppelin-contracts/contracts/token/ERC721/extensions/ERC721Enumerable.sol#L4)
		-[^0.8.20](lib/openzeppelin-contracts/contracts/token/ERC721/extensions/IERC721Enumerable.sol#L4)
		-[^0.8.20](lib/openzeppelin-contracts/contracts/token/ERC721/extensions/IERC721Metadata.sol#L4)
		-[^0.8.20](lib/openzeppelin-contracts/contracts/token/ERC721/utils/ERC721Utils.sol#L4)
		-[^0.8.20](lib/openzeppelin-contracts/contracts/utils/Context.sol#L4)
		-[^0.8.20](lib/openzeppelin-contracts/contracts/utils/Panic.sol#L4)
		-[^0.8.20](lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol#L4)
		-[^0.8.20](lib/openzeppelin-contracts/contracts/utils/Strings.sol#L4)
		-[^0.8.20](lib/openzeppelin-contracts/contracts/utils/introspection/ERC165.sol#L4)
		-[^0.8.20](lib/openzeppelin-contracts/contracts/utils/introspection/IERC165.sol#L4)
		-[^0.8.20](lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L4)
		-[^0.8.20](lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol#L5)
		-[^0.8.20](lib/openzeppelin-contracts/contracts/utils/math/SignedMath.sol#L4)
	- Version constraint 0.8.26 is used by:
		-[0.8.26](lib/protocol-core-v1/contracts/interfaces/modules/base/IModule.sol#L2)
		-[0.8.26](lib/protocol-core-v1/contracts/interfaces/modules/licensing/ILicenseTemplate.sol#L2)
		-[0.8.26](lib/protocol-core-v1/contracts/interfaces/modules/licensing/ILicensingModule.sol#L2)
		-[0.8.26](lib/protocol-core-v1/contracts/interfaces/modules/royalty/IRoyaltyModule.sol#L2)
		-[0.8.26](lib/protocol-core-v1/contracts/interfaces/registries/IIPAccountRegistry.sol#L2)
		-[0.8.26](lib/protocol-core-v1/contracts/interfaces/registries/IIPAssetRegistry.sol#L2)
		-[0.8.26](lib/protocol-core-v1/contracts/interfaces/registries/ILicenseRegistry.sol#L2)
		-[0.8.26](lib/protocol-core-v1/contracts/lib/Licensing.sol#L2)
		-[0.8.26](src/RoyaltyModule.sol#L2)
		-[0.8.26](src/core/LendingProtocol.sol#L2)
		-[0.8.26](src/core/RangeValidator.sol#L2)
		-[0.8.26](src/core/Stash.sol#L2)
		-[0.8.26](src/core/lending/AdminManager.sol#L2)
		-[0.8.26](src/core/lending/LoanManager.sol#L2)
		-[0.8.26](src/core/lending/OfferManager.sol#L2)
		-[0.8.26](src/core/lending/RefinanceManager.sol#L2)
		-[0.8.26](src/core/lending/RequestManager.sol#L2)
		-[0.8.26](src/core/manager/CollectionManager.sol#L2)
		-[0.8.26](src/core/manager/CurrencyManager.sol#L2)
		-[0.8.26](src/core/manager/RoyaltyManager.sol#L2)
		-[0.8.26](src/interfaces/ICollectionManager.sol#L2)
		-[0.8.26](src/interfaces/ICurrencyManager.sol#L2)
		-[0.8.26](src/interfaces/ILendingProtocol.sol#L2)
		-[0.8.26](src/interfaces/ILiquidation.sol#L2)
		-[0.8.26](src/interfaces/IPurchaseBundler.sol#L2)
		-[0.8.26](src/interfaces/IRangeValidator.sol#L2)
		-[0.8.26](src/interfaces/IRoyaltyManager.sol#L2)
		-[0.8.26](src/interfaces/IStash.sol#L2)
		-[0.8.26](src/interfaces/IStoryProtocolAccess.sol#L2)
		-[0.8.26](src/mocks/ERC20Mock.sol#L5)
		-[0.8.26](src/mocks/ERC721Mock.sol#L5)
		-[0.8.26](src/mocks/MockIIPAssetRegistry.sol#L2)
		-[0.8.26](src/mocks/MockIPAssetRegistry.sol#L2)
		-[0.8.26](src/mocks/MockLendingProtocol.sol#L2)
		-[0.8.26](src/mocks/MockRoyaltyModule.sol#L2)

lib/openzeppelin-contracts/contracts/access/Ownable.sol#L4


## costly-loop
Impact: Informational
Confidence: Medium
 - [ ] ID-84
[CollectionManager.removeWhitelistedCollection(address)](src/core/manager/CollectionManager.sol#L55-L69) has costly operations inside a loop:
	- [collectionList.pop()](src/core/manager/CollectionManager.sol#L64)

src/core/manager/CollectionManager.sol#L55-L69


## dead-code
Impact: Informational
Confidence: Medium
 - [ ] ID-85
[LoanManager._getIpAssetRegistry()](src/core/lending/LoanManager.sol#L55-L58) is never used and should be removed

src/core/lending/LoanManager.sol#L55-L58


 - [ ] ID-86
[LoanManager._getCollectionManager()](src/core/lending/LoanManager.sol#L50-L53) is never used and should be removed

src/core/lending/LoanManager.sol#L50-L53


 - [ ] ID-87
[OfferManager._getCollectionManager()](src/core/lending/OfferManager.sol#L33-L37) is never used and should be removed

src/core/lending/OfferManager.sol#L33-L37


 - [ ] ID-88
[RefinanceManager._addLoan(bytes32,ILendingProtocol.Loan)](src/core/lending/RefinanceManager.sol#L85) is never used and should be removed

src/core/lending/RefinanceManager.sol#L85


 - [ ] ID-89
[AdminManager._setIpAssetRegistry(IIPAssetRegistry)](src/core/lending/AdminManager.sol#L54-L56) is never used and should be removed

src/core/lending/AdminManager.sol#L54-L56


 - [ ] ID-90
[RefinanceManager._setLoanStatus(bytes32,ILendingProtocol.LoanStatus)](src/core/lending/RefinanceManager.sol#L78) is never used and should be removed

src/core/lending/RefinanceManager.sol#L78


 - [ ] ID-91
[AdminManager._setRoyaltyManager(IRoyaltyManager)](src/core/lending/AdminManager.sol#L50-L52) is never used and should be removed

src/core/lending/AdminManager.sol#L50-L52


 - [ ] ID-92
[ERC721Mock._increaseBalance(address,uint128)](src/mocks/ERC721Mock.sol#L78-L80) is never used and should be removed

src/mocks/ERC721Mock.sol#L78-L80


 - [ ] ID-93
[LoanManager._getLoanOffer(bytes32)](src/core/lending/LoanManager.sol#L70-L90) is never used and should be removed

src/core/lending/LoanManager.sol#L70-L90


 - [ ] ID-94
[RefinanceManager._getLoan(bytes32)](src/core/lending/RefinanceManager.sol#L55-L76) is never used and should be removed

src/core/lending/RefinanceManager.sol#L55-L76


 - [ ] ID-95
[RequestManager._getCollectionManager()](src/core/lending/RequestManager.sol#L23-L25) is never used and should be removed

src/core/lending/RequestManager.sol#L23-L25


 - [ ] ID-96
[AdminManager._setCurrencyManager(ICurrencyManager)](src/core/lending/AdminManager.sol#L34-L36) is never used and should be removed

src/core/lending/AdminManager.sol#L34-L36


 - [ ] ID-97
[LoanManager._getPurchaseBundler()](src/core/lending/LoanManager.sol#L65-L68) is never used and should be removed

src/core/lending/LoanManager.sol#L65-L68


 - [ ] ID-98
[LoanManager._incrementLoanCounter()](src/core/lending/LoanManager.sol#L461-L464) is never used and should be removed

src/core/lending/LoanManager.sol#L461-L464


 - [ ] ID-99
[RequestManager._getCurrencyManager()](src/core/lending/RequestManager.sol#L19-L21) is never used and should be removed

src/core/lending/RequestManager.sol#L19-L21


 - [ ] ID-100
[LoanManager._getLoanRequest(bytes32)](src/core/lending/LoanManager.sol#L95-L97) is never used and should be removed

src/core/lending/LoanManager.sol#L95-L97


 - [ ] ID-101
[LoanManager._getCurrencyManager()](src/core/lending/LoanManager.sol#L45-L48) is never used and should be removed

src/core/lending/LoanManager.sol#L45-L48


 - [ ] ID-102
[LoanManager._setLoanRequestInactive(bytes32)](src/core/lending/LoanManager.sol#L99-L101) is never used and should be removed

src/core/lending/LoanManager.sol#L99-L101


 - [ ] ID-103
[AdminManager._setLiquidationContract(ILiquidation)](src/core/lending/AdminManager.sol#L42-L44) is never used and should be removed

src/core/lending/AdminManager.sol#L42-L44


 - [ ] ID-104
[AdminManager._setCollectionManager(ICollectionManager)](src/core/lending/AdminManager.sol#L38-L40) is never used and should be removed

src/core/lending/AdminManager.sol#L38-L40


 - [ ] ID-105
[RefinanceManager._getCurrencyManager()](src/core/lending/RefinanceManager.sol#L99-L102) is never used and should be removed

src/core/lending/RefinanceManager.sol#L99-L102


 - [ ] ID-106
[RefinanceManager._updateLoanAfterRenegotiation(bytes32,uint256,uint256,uint64)](src/core/lending/RefinanceManager.sol#L92-L97) is never used and should be removed

src/core/lending/RefinanceManager.sol#L92-L97


 - [ ] ID-107
[RefinanceManager._calculateInterest(bytes32)](src/core/lending/RefinanceManager.sol#L87-L90) is never used and should be removed

src/core/lending/RefinanceManager.sol#L87-L90


 - [ ] ID-108
[OfferManager._getCurrencyManager()](src/core/lending/OfferManager.sol#L27-L31) is never used and should be removed

src/core/lending/OfferManager.sol#L27-L31


 - [ ] ID-109
[LoanManager._setLoanOfferInactive(bytes32)](src/core/lending/LoanManager.sol#L92) is never used and should be removed

src/core/lending/LoanManager.sol#L92


 - [ ] ID-110
[AdminManager._setPurchaseBundler(IPurchaseBundler)](src/core/lending/AdminManager.sol#L46-L48) is never used and should be removed

src/core/lending/AdminManager.sol#L46-L48


 - [ ] ID-111
[LoanManager._getRoyaltyManager()](src/core/lending/LoanManager.sol#L60-L63) is never used and should be removed

src/core/lending/LoanManager.sol#L60-L63


## solc-version
Impact: Informational
Confidence: High
 - [ ] ID-112
Version constraint ^0.8.20 contains known severe issues (https://solidity.readthedocs.io/en/latest/bugs.html)
	- VerbatimInvalidDeduplication
	- FullInlinerNonExpressionSplitArgumentEvaluationOrder
	- MissingSideEffectsOnSelectorAccess.
It is used by:
	- [^0.8.20](lib/openzeppelin-contracts/contracts/access/Ownable.sol#L4)
	- [^0.8.20](lib/openzeppelin-contracts/contracts/interfaces/IERC1363.sol#L4)
	- [^0.8.20](lib/openzeppelin-contracts/contracts/interfaces/IERC165.sol#L4)
	- [^0.8.20](lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol#L4)
	- [^0.8.20](lib/openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol#L3)
	- [^0.8.20](lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol#L4)
	- [^0.8.20](lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol#L4)
	- [^0.8.20](lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol#L4)
	- [^0.8.20](lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol#L4)
	- [^0.8.20](lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol#L4)
	- [^0.8.20](lib/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol#L4)
	- [^0.8.20](lib/openzeppelin-contracts/contracts/token/ERC721/IERC721.sol#L4)
	- [^0.8.20](lib/openzeppelin-contracts/contracts/token/ERC721/IERC721Receiver.sol#L4)
	- [^0.8.20](lib/openzeppelin-contracts/contracts/token/ERC721/extensions/ERC721Burnable.sol#L4)
	- [^0.8.20](lib/openzeppelin-contracts/contracts/token/ERC721/extensions/ERC721Enumerable.sol#L4)
	- [^0.8.20](lib/openzeppelin-contracts/contracts/token/ERC721/extensions/IERC721Enumerable.sol#L4)
	- [^0.8.20](lib/openzeppelin-contracts/contracts/token/ERC721/extensions/IERC721Metadata.sol#L4)
	- [^0.8.20](lib/openzeppelin-contracts/contracts/token/ERC721/utils/ERC721Utils.sol#L4)
	- [^0.8.20](lib/openzeppelin-contracts/contracts/utils/Context.sol#L4)
	- [^0.8.20](lib/openzeppelin-contracts/contracts/utils/Panic.sol#L4)
	- [^0.8.20](lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol#L4)
	- [^0.8.20](lib/openzeppelin-contracts/contracts/utils/Strings.sol#L4)
	- [^0.8.20](lib/openzeppelin-contracts/contracts/utils/introspection/ERC165.sol#L4)
	- [^0.8.20](lib/openzeppelin-contracts/contracts/utils/introspection/IERC165.sol#L4)
	- [^0.8.20](lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L4)
	- [^0.8.20](lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol#L5)
	- [^0.8.20](lib/openzeppelin-contracts/contracts/utils/math/SignedMath.sol#L4)

lib/openzeppelin-contracts/contracts/access/Ownable.sol#L4


## low-level-calls
Impact: Informational
Confidence: High
 - [ ] ID-113
Low level call in [AdminManager.emergencyWithdrawNative(address,uint256)](src/core/lending/AdminManager.sol#L140-L143):
	- [(success,None) = to.call{value: amount}()](src/core/lending/AdminManager.sol#L141)

src/core/lending/AdminManager.sol#L140-L143


## naming-convention
Impact: Informational
Confidence: High
 - [ ] ID-114
Variable [RoyaltyManager.LICENSE_REGISTRY](src/core/manager/RoyaltyManager.sol#L28) is not in mixedCase

src/core/manager/RoyaltyManager.sol#L28


 - [ ] ID-115
Variable [MockRoyaltyModule._ipRoyaltyVaults_mock_state](src/mocks/MockRoyaltyModule.sol#L12) is not in mixedCase

src/mocks/MockRoyaltyModule.sol#L12


 - [ ] ID-116
Variable [RoyaltyManager.LICENSING_MODULE](src/core/manager/RoyaltyManager.sol#L26) is not in mixedCase

src/core/manager/RoyaltyManager.sol#L26


 - [ ] ID-117
Variable [RoyaltyManager.IP_ASSET_REGISTRY](src/core/manager/RoyaltyManager.sol#L22) is not in mixedCase

src/core/manager/RoyaltyManager.sol#L22


 - [ ] ID-118
Variable [RoyaltyManager.ROYALTY_MODULE](src/core/manager/RoyaltyManager.sol#L24) is not in mixedCase

src/core/manager/RoyaltyManager.sol#L24


## too-many-digits
Impact: Informational
Confidence: Medium
 - [ ] ID-119
[Math.log2(uint256)](lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L612-L651) uses literals with too many digits:
	- [r = r | byte(uint256,uint256)(x >> r,0x0000010102020202030303030303030300000000000000000000000000000000)](lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L649)

lib/openzeppelin-contracts/contracts/utils/math/Math.sol#L612-L651


## unused-state
Impact: Informational
Confidence: High
 - [ ] ID-120
[MockRoyaltyModule._ipRoyaltyVaults_mock_state](src/mocks/MockRoyaltyModule.sol#L12) is never used in [MockRoyaltyModule](src/mocks/MockRoyaltyModule.sol#L8-L155)

src/mocks/MockRoyaltyModule.sol#L12


## constable-states
Impact: Optimization
Confidence: High
 - [ ] ID-121
[MockIPAssetRegistry._ipAccountImpl](src/mocks/MockIPAssetRegistry.sol#L13) should be constant 

src/mocks/MockIPAssetRegistry.sol#L13


## var-read-using-this
Impact: Optimization
Confidence: High
 - [ ] ID-122
The function [LoanManager.buyCollateralAndRepay(bytes32,uint256)](src/core/lending/LoanManager.sol#L322-L341) reads [interest = this.calculateInterest(loanId)](src/core/lending/LoanManager.sol#L326) with `this` which adds an extra STATICCALL.

src/core/lending/LoanManager.sol#L322-L341


 - [ ] ID-123
The function [LendingProtocol.proposeRenegotiation(bytes32,uint256,uint256,uint256)](src/core/LendingProtocol.sol#L240-L260) reads [loan = this.getLoan(loanId)](src/core/LendingProtocol.sol#L249) with `this` which adds an extra STATICCALL.

src/core/LendingProtocol.sol#L240-L260


 - [ ] ID-124
The function [LoanManager.claimAndRepay(bytes32)](src/core/lending/LoanManager.sol#L225-L271) reads [interest = this.calculateInterest(loanId)](src/core/lending/LoanManager.sol#L244) with `this` which adds an extra STATICCALL.

src/core/lending/LoanManager.sol#L225-L271


 - [ ] ID-125
The function [LendingProtocol._calculateInterest(bytes32)](src/core/LendingProtocol.sol#L143-L145) reads [this.calculateInterest(loanId)](src/core/LendingProtocol.sol#L144) with `this` which adds an extra STATICCALL.

src/core/LendingProtocol.sol#L143-L145


 - [ ] ID-126
The function [LoanManager.repayLoan(bytes32)](src/core/lending/LoanManager.sol#L208-L223) reads [interest = this.calculateInterest(loanId)](src/core/lending/LoanManager.sol#L214) with `this` which adds an extra STATICCALL.

src/core/lending/LoanManager.sol#L208-L223


 - [ ] ID-127
The function [LendingProtocol._getLoan(bytes32)](src/core/LendingProtocol.sol#L116-L118) reads [this.getLoan(loanId)](src/core/LendingProtocol.sol#L117) with `this` which adds an extra STATICCALL.

src/core/LendingProtocol.sol#L116-L118


 - [ ] ID-128
The function [LendingProtocol._getLoanOffer(bytes32)](src/core/LendingProtocol.sol#L101-L108) reads [this.getLoanOffer(offerId)](src/core/LendingProtocol.sol#L107) with `this` which adds an extra STATICCALL.

src/core/LendingProtocol.sol#L101-L108


