// SPDX-License-Identifier: MIT
pragma solidity >= 0.4.22 < 0.9.0;

/// @title AcquaCoin smart contract version 0.1
/// @author Anatoli Ivanou: GitHub: Cyfirr
/// @notice Developed for AcquaCoin application for EBC9, Barcelona, Oct.25.2023
contract AcquaCoin {

    /// @notice Mandatory ERC-20 token fields (not final yet)
	string public name = "AcquaCoin";
	string public symbol = "ACQA";
	uint public totalsupply = 100000000000000000;
	uint public decimal = 18;

    /// @notice Event is fired once the transfer occurs
	event Transfer(
		address indexed _from,
		address indexed _to,
		uint _value
	);

    /// @notice Event is fired once the transfer is approved
	event Approve(
		address indexed _owner,
		address indexed _spender,
		uint _value
	);

    /// @notice Event is fired once this smart contract receives data from the IoT sensor (i.e. water counter)
    event DataReceived(
        string indexed _measurement,
        string indexed _sensor,
        string indexed _type,
        uint256 _value
    );

    /// @notice Structure having hash of the measurement pushed from the sensor and sensor data
    struct Measurement {
        string measurementHash;
        Sensor sensor;
    }

    /// @notice Structure having the data of the sensor and measurement value
    struct Sensor {
        string sensorHash;
        string sensorType;
        string location;
        string company;
        uint256 value;
    }

    /// @notice Array keeping all the measurements
    Measurement[] public measurements;
    /// @notice Array keeping all the sensors data
    Sensor[] public sensors;

    /// @notice Mapping for the balances (mapped to addresses)
	mapping( address => uint256 ) public balance;
    /// @notice Mapping for the allowance (from, to, balance) used for approval
	mapping( address => mapping( address => uint256 ) ) public allowance;
    /// @notice mapping of sensors hashes to addresses (can be used if many sensors will have same wallet based on location or company)
    mapping( string => address ) public sensorAddress;
    /// @notice Mapping of sensor hashes to company locations to company names (may get deprecated)
    mapping( string => mapping( string => string )) sensorToLocationToCompany;
    /// @notice mapping of sensors hashes to sensor types (may get deprecated)
    mapping( string => string ) sensorToSensorType;
    /// @notice mapping of sensors hashes to the latest known value sent by sensors
    mapping( string => uint256) sensorToValue;
    
    /// @notice hard-coded limit for the electricity usage to define incentivisation ammounts
    uint256 public constant LIGHT_LIMIT = 500;
    /// @notice hard-coded limit for the water usage to define incentivisation ammounts
    uint256 public constant WATER_LIMIT = 100;
    /// @notice hard-coded limit for the gas usage to define incentivisation ammounts
    uint256 public constant GAS_LIMIT = 50;

    /// @notice hard-coded sensor type name (change later to units?)
    string public constant LIGHT = "LIGHT";
    /// @notice hard-coded sensor type name (change later to units?)
    string public constant WATER = "WATER";
    /// @notice hard-coded sensor type name (change later to units?)
    string public constant GAS = "GAS";

    /// @notice constructor, will assign total supply once instanciated
	constructor() {
		balance [msg.sender] = totalsupply;
	}

    /// @notice adds sensor to needed mappings and array of sensors. Has to be done by some API to allow this contract to work properly.
    /// @param _sensorHash hash of sensor
    /// @param _type type of sensor (currently 3 of them are supported)
    /// @param _location location of the sensor
    /// @param _company company the sensor does belong to
    function addSensor(string memory _sensorHash, string memory _type, string memory _location, string memory _company) public {
        if (sensorExists(_sensorHash)) {
            revert("Sensor already exists.");
        }
        sensors.push(Sensor(_sensorHash, _type, _location, _company, 0));
        sensorToSensorType[_sensorHash] = _type;
        sensorAddress[_sensorHash] = msg.sender;
        sensorToLocationToCompany[_sensorHash][_location] = _company;
        sensorToValue[_sensorHash] = 0;
    }

    /// @notice Sets type of sensor for an existing sensor. Will throw an error if sensor doesn't exist.
    /// @param _sensorHash hash of sensor
    /// @param _type type of sensor (currently 3 of them are supported)
    function setSensorType(string memory _sensorHash, string memory _type) public {
        require (bytes(_sensorHash).length > 0);
        require (keccak256(abi.encodePacked(_type)) == keccak256(abi.encodePacked(LIGHT)) ||
                keccak256(abi.encodePacked(_type)) == keccak256(abi.encodePacked(WATER)) ||
                keccak256(abi.encodePacked(_type)) == keccak256(abi.encodePacked(GAS)) );
        sensorToSensorType[_sensorHash] = _type;
        sensors[findSensorBySensorHash(_sensorHash)].sensorType = _type;
    }

    /// @notice Returns an index of a sensor found by hash in the sensors array
    /// @param _sensorHash hash of sensor
    /// @return index sensor's index in the sensors array. Throws an error if sensor doesn't exist
    function findSensorBySensorHash(string memory _sensorHash) public view returns (uint256 index) {
        for (uint256 i = 0; i < sensors.length; i++) {
             if (keccak256(abi.encodePacked((sensors[i].sensorHash))) == keccak256(abi.encodePacked((_sensorHash)))) {
                return i;
             }
        }
        revert("Sensor does not exist"); 
    }

    /// @notice Checks if sensor exists in sensors array looking up by its hash
    /// @param _sensorHash hash of sensor
    /// @return exists true if sensor exists, otherwise - false
    function sensorExists(string memory _sensorHash) public view returns (bool exists) {
            for (uint256 i = 0; i < sensors.length; i++) {
                if (keccak256(abi.encodePacked((sensors[i].sensorHash))) == keccak256(abi.encodePacked((_sensorHash)))) {
                    return true;
                }
            }
        return false;
    }

    /// @notice adds sensor's wallet address to the hash-address mapping (can be used to map many sensors to the same address, for instance). Sensor's address should be set before any token transfers are done.
    /// @param _sensorHash hash of sensor
    function addSensorAddress(string memory _sensorHash) public {
        require (bytes(_sensorHash).length > 0);
        sensorAddress[_sensorHash] = msg.sender;
    }

    /// @notice sets location and company for the sensor in array and in mappings. Sensor should exist.
    /// @param _sensorHash hash of sensor
    /// @param _location location to set
    /// @param _company company to set
    function setSensorToLocationToCompany(string memory _sensorHash, string memory _location, string memory _company) public {
        require (bytes(_sensorHash).length > 0);
        require (bytes(_location).length > 0);
        require (bytes(_company).length > 0);
        sensorToLocationToCompany[_sensorHash][_location] = _company;
        uint256 sensorIndex = findSensorBySensorHash(_sensorHash);
        sensors[sensorIndex].location = _location;
        sensors[sensorIndex].company = _company;
    }

    /// @notice Should be used to push data (measurements) from sensors to this smart contract. Updates relevant mappings and measurements array. Sensor should be existing in smart contract upfront.
    /// @param _measurementHash hash of measurement (always unique per sensor).
    /// @param _sensorHash hash of sensor
    /// @param _type sensor's type
    /// @param _value sensor's measurement value (i.e. how many liters of water).
    /// @return success true if data for the sensor was added. Otherwise - an error.
    function pushData(string memory _measurementHash, string memory _sensorHash, string memory _type, uint256 _value) public returns (bool success) {
        require (bytes(_measurementHash).length > 0);
        require (bytes(_sensorHash).length > 0);
        require (keccak256(abi.encodePacked(_type)) == keccak256(abi.encodePacked(LIGHT)) ||
                keccak256(abi.encodePacked(_type)) == keccak256(abi.encodePacked(WATER)) ||
                keccak256(abi.encodePacked(_type)) == keccak256(abi.encodePacked(GAS)) );
        require (_value >= 0);
        emit DataReceived(_measurementHash, _sensorHash, _type, _value);
        uint256 newValue = sensorToValue[_sensorHash] + _value;
        sensorToValue[_sensorHash] = newValue;
        Sensor memory foundSensor = sensors[findSensorBySensorHash(_sensorHash)];     
        measurements.push(Measurement(_measurementHash, Sensor(_sensorHash, _type, foundSensor.location, foundSensor.company, newValue)));
        return true;
    }

    /// @notice Returns sensor's measurement value by sensor's hash. It can be used by API to send info to Front-end
    /// @param _sensorHash hash of sensor to use in lookup
    /// @return sensorValue value associated to sensor (latest known).
    function pullValueBySensorHash(string memory _sensorHash) view  public returns (uint256 sensorValue) {
        return sensorToValue[_sensorHash];
    }

    /// @notice Returns sensors measurement value aggregated by location. It can be used by API to send info to Front-end
    /// @param _location hash of sensor to use in lookup
    /// @return sensorsValue value associated to location as summary of all the sensors measuremnt for this location (latest known).
    function pullValueByLocation(string memory _location) view  public returns (uint256 sensorsValue) {
        uint256 aggregatedByLocation = 0;
        for (uint256 i = 0; i < sensors.length; i++) {
            if (keccak256(abi.encodePacked(sensors[i].location)) == keccak256(abi.encodePacked(_location))) {
                aggregatedByLocation += sensors[i].value;
            }
        }
        return aggregatedByLocation;
    }

    /// @notice Returns sensors measurement value aggregated by company. It can be used by API to send info to Front-end
    /// @param _company hash of sensor to use in lookup
    /// @return sensorsValue value associated to company as summary of all the sensors measuremnt for this company (latest known).
    function pullValueByCompany(string memory _company) view public returns (uint256 sensorsValue) {
        uint256 aggregatedByCompany = 0;
        for (uint256 i = 0; i < sensors.length; i++) {
            if (keccak256(abi.encodePacked(sensors[i].company)) == keccak256(abi.encodePacked(_company))) {
                aggregatedByCompany += sensors[i].value;
            }
        }
        return aggregatedByCompany;
    }

    /// @notice Returns the difference between set limit and consumed water, gas, electricity for the sensor. 
    /// @param _sensor hash of sensor to use in lookup
    /// @return rewardAmmount the difference between limit and actual consumption
    function checkLimit(string memory _sensor) view  public returns (uint256 rewardAmmount) {
        require(bytes(_sensor).length > 0);
        string memory _type = sensorToSensorType[_sensor];
        require (keccak256(abi.encodePacked(_type)) == keccak256(abi.encodePacked(LIGHT)) ||
                keccak256(abi.encodePacked(_type)) == keccak256(abi.encodePacked(WATER)) ||
                keccak256(abi.encodePacked(_type)) == keccak256(abi.encodePacked(GAS)) );
        uint256 _value = sensorToValue[_sensor];
        return checkLimit(_type, _value);
    }

    /// @notice Returns the difference between set limit and consumed water, gas, electricity for the sensor. Just a test method, to be potentially changed
    /// @param _type sensor type to be used in calculation
    /// @param _value actual consumption to be used in calculation
    /// @return rewardAmmount the difference between limit and actual consumption
    function checkLimit(string memory _type, uint256 _value) pure public returns (uint256 rewardAmmount) {
        if (keccak256(abi.encodePacked(_type)) == keccak256(abi.encodePacked(LIGHT))) {
            return LIGHT_LIMIT - _value;
        }
        if (keccak256(abi.encodePacked(_type)) == keccak256(abi.encodePacked(WATER))) {
            return WATER_LIMIT - _value;
        }
        if (keccak256(abi.encodePacked(_type)) == keccak256(abi.encodePacked(GAS))) {
            return GAS_LIMIT - _value;
        }
    }

    /// @notice does the reward transfer to sensor's wallet address if actual consumption is less than set limit 
    /// @param _sensor sensor hash
    /// @return success Returns true if successful
    function reward(string memory _sensor) public returns (bool success) {
        uint belowLimit = checkLimit(_sensor);
        if (belowLimit > 0) {
            transfer(sensorAddress[_sensor], belowLimit);
        }
        return true;
    }

    /// Transfers funds from the contract to recepient.
	function transfer (address _to, uint256 _value) public returns(bool success) {
		require(balance[msg.sender] >= _value);
		balance[msg.sender] -= _value;
		balance[_to] += _value;
		emit Transfer(msg.sender, _to, _value);
		return true;
	}

    /// Approves the transfer
	function approve (address _spender, uint256 _value) public returns(bool success) {
		allowance[msg.sender][_spender] = _value;
		emit Approve(msg.sender, _spender, _value);
		return true;
	}

    /// Transfers funds from one address to another one
	function transferfrom (address _from, address _to, uint256 _value) public returns(bool success) {
		require(_value <= balance[_from]);
		require(_value <= allowance[_from][msg.sender]);
		balance[_from] -= _value;
		balance[_to] += _value;
		allowance[_from][msg.sender] -= _value;
		emit Transfer (_from, _to, _value);
		return true;
	}
}