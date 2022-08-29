// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.16;
import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol'; 
import '@openzeppelin/contracts/access/Ownable.sol';
//import './owner.sol';

/*
interface IERC20 {

    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);

    function transfer(address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);


    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}
*/


contract SampleToken is IERC20 {
    using SafeMath for uint256;

    string public constant name = "SampleToken";
    string public constant symbol = "SMT";
    uint8 public constant decimals = 18;

    mapping(address => uint256) balances;
    mapping(address => mapping (address => uint256)) allowed;

    uint256 totalSupply_;

    constructor(uint256 total) {
        totalSupply_ = total;
        balances[msg.sender] = totalSupply_;
    }

    function totalSupply() public override view returns (uint256) {
        return totalSupply_;
    }

    function balanceOf(address tokenOwner) public override view returns (uint256) {
        return balances[tokenOwner];
    }

    function transfer(address receiver, uint256 numTokens) public override returns (bool) {
        require(numTokens <= balances[msg.sender]);
        balances[msg.sender] = balances[msg.sender].sub(numTokens);
        balances[receiver] = balances[receiver].add(numTokens);
        emit Transfer(msg.sender, receiver, numTokens);
        return true;
    }

    function approve(address delegate, uint256 numTokens) public override returns (bool) {
        allowed[msg.sender][delegate] = numTokens;
        emit Approval(msg.sender, delegate, numTokens);
        return true;
    }

    function allowance(address owner, address delegate) public override view returns (uint) {
        return allowed[owner][delegate];
    }

    function transferFrom(address owner, address buyer, uint256 numTokens) public override returns (bool) {
        require(numTokens <= balances[owner]);
        require(numTokens <= allowed[owner][msg.sender]);

        balances[owner] = balances[owner].sub(numTokens);
        allowed[owner][msg.sender] = allowed[owner][msg.sender].sub(numTokens);
        balances[buyer] = balances[buyer].add(numTokens);
        emit Transfer(owner, buyer, numTokens);
        return true;
    }
}


contract PrestaVault is Ownable {
    IERC20 public immutable token;

    address addressFees;
    uint private contratKey;
    uint private fees;
    uint private feesCancel;
    enum prestaStatus { WAIT, COMPLETED, CANCELED }

    struct presta {
        address from;
        address to;
        uint amount;
        uint amount_fees;
        prestaStatus status;
    }
    mapping(uint => presta) public prestas;

    //Liste des presta par sender
    mapping(address => uint[]) public prestaBySender;
    //Liste des presta pour un bénéficiaire
    mapping(address => uint[]) public prestaForRecipient;

    event prestaAdded(address _form, address _to, uint _amount, uint _contratKey, uint _date);

    /**
     * 
     */
    constructor(address _token) {
        addressFees = address(this);//L'adresse où iront les fees
        fees = 5;//Par défaut 5%
        feesCancel = 0;//Par défaut pas de frais d'annulation
        token = IERC20(_token); //Le token que l'on pourra échanger
    }

    /**
     * Permet de changer l adresse qui va recevoir les fees
     */
    function setAddressFees(address _address) external onlyOwner {
        addressFees = _address;
    }

    /**
     * Permet de changer les fees
     */
    function setFees(uint _fees) external onlyOwner {
        fees = _fees;
    }

    /**
     * Permet de changer les fees d'annulation
     */
    function setFeesCancel(uint _feesCancel) external onlyOwner {
        feesCancel = _feesCancel;
    }

    /**
     * Créé une nouvelle prestation
     */
    function createPresta(uint _amount, address _to) external returns (uint) {
        require( msg.sender != address(this) , "Can't send to himself");

        contratKey++;//Nouveau contrat
        uint amount_fees = SafeMath.div(SafeMath.mul(_amount, fees),100);
        prestas[contratKey] = presta({from:msg.sender, to:_to, amount:_amount, amount_fees: amount_fees, status:prestaStatus.WAIT});
        prestaBySender[msg.sender].push(contratKey);
        prestaForRecipient[_to].push(contratKey);
        
        token.transferFrom(msg.sender, address(this), _amount);

        emit prestaAdded(msg.sender, _to, _amount, contratKey, block.timestamp);

        return contratKey;
    }


    /**
     * Valide une transaction et envoi l'argent à _to
     */
    function validTransfertPresta(uint _contratKey) external {

        require(prestas[_contratKey].from == msg.sender || owner() == msg.sender , "Yout must be the sender");
        require(prestas[_contratKey].status == prestaStatus.WAIT, "Presta is not waiting");
        
        token.transfer(prestas[_contratKey].to, prestas[_contratKey].amount - prestas[_contratKey].amount_fees); //j'envoi au to sans les fees
        token.transfer(addressFees, prestas[_contratKey].amount_fees);//J'envoi à l'adresse qui recoit les fees

        prestas[_contratKey].status = prestaStatus.COMPLETED;
        
        //deletePrestaOfSender(prestas[_contratKey].from, _contratKey);ne fonctionne pas
    }

    /**
     * Annule une transaction et renvoi l'argent à _from
     */
    function cancelTransfertPresta(uint _contratKey) external {
        require(prestas[_contratKey].from == msg.sender || owner() == msg.sender, "Yout must be the sender");
        require(prestas[_contratKey].status == prestaStatus.WAIT, "Presta is not waiting");
        
        if(feesCancel == 0){
            token.transfer(prestas[_contratKey].from, prestas[_contratKey].amount);//Je renvoi tout à l'adresse from
        } else {
            //Frais d'annulation toujours calculés en live
            uint amount_fees = SafeMath.div(SafeMath.mul(prestas[_contratKey].amount, feesCancel),100);
            token.transfer(prestas[_contratKey].from, prestas[_contratKey].amount - amount_fees); //j'envoi au from sans les fees d annulation
            token.transfer(addressFees, amount_fees);//J'envoi à l'adresse qui recoit les fees d annulation
        }

        prestas[_contratKey].status = prestaStatus.CANCELED;
        
    }

    /**
     * Retourne le nombre de prestations envoyés par cette personne dans le status souhaité
     */
    function getNumberPrestaOfSender(address _address, prestaStatus _status) public view returns (uint) {
        uint nbPresta;
        for (uint j = 0; j<=prestaBySender[_address].length-1; j++){
            if(prestas[prestaBySender[_address][j]].status == _status){
                nbPresta++;
            }
        }
        return nbPresta;
    }

    /**
     * Retourne les prestations envoyés par la personne connectée
     */
    function getPrestaOfSender() public view returns  ( presta[] memory) {
        /*
        presta[] memory prestasTmp;
        for (uint j = 0; j<=prestaBySender[msg.sender].length-1; j++){
            prestasTmp[j] = prestas[prestaBySender[msg.sender][j]];
        }
        return prestasTmp;
        */
        uint  prestaCount = prestaBySender[msg.sender].length;
        presta[]  memory prestasTmp = new presta[](prestaCount);
        for (uint j = 0; j<prestaCount; j++){
            presta storage p = prestas[prestaBySender[msg.sender][j]];
                prestasTmp[j] = p;
        }
        return prestasTmp;

    }

    /**
     * Retourne les prestations pour la personne connectée
     */
    function getPrestaForRecipient() public view returns  ( presta[] memory) {
        /*presta[] memory prestasTmp;
        for (uint j = 0; j<=prestaForRecipient[msg.sender].length-1; j++){
            prestasTmp[j] = prestas[prestaForRecipient[msg.sender][j]];
        }*/
        uint  prestaCount = prestaForRecipient[msg.sender].length;
        presta[]  memory prestasTmp = new presta[](prestaCount);
        for (uint j = 0; j<prestaCount; j++){
            presta storage p = prestas[prestaForRecipient[msg.sender][j]];
            prestasTmp[j] = p;
        }
        return prestasTmp;
    }

}



contract PrestaDispute is Ownable {

}
