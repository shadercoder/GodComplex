////////////////////////////////////////////////////////////////////////////////
// Shaders to compute HBIL
////////////////////////////////////////////////////////////////////////////////
//

//#define AVERAGE_COSINES 1
//#define USE_NUMERICAL_INTEGRATION 256	// Define this to compute bent normal numerically (value = integration steps count)

#include "Global.hlsl"
#include "HBIL.hlsl"

static const float	GATHER_SPHERE_MAX_RADIUS_P = 200.0;	// Maximum radius (in pixels) that we allow our sphere to get

#define MAX_ANGLES	16									// Amount of circle subdivisions per pixel
#define MAX_SAMPLES	16									// Maximum amount of samples per circle subdivision

Texture2D< float >	_tex_depth : register(t0);			// Depth or distance buffer (here we're given depth)
Texture2D< float4 >	_tex_sourceRadiance : register(t1);	// Last frame's reprojected radiance buffer
Texture2D< float4 >	_tex_normal : register(t2);			// Camera-space normal vectors
Texture2D< float >	_tex_blueNoise : register(t3);

cbuffer CB_HBIL : register( b3 ) {
	float4	_bilateralValues;
	float	_gatherSphereMaxRadius_m;		// Radius of the sphere that will gather our irradiance samples (in meters)
};

float4	VS( float4 __Position : SV_POSITION ) : SV_POSITION { return __Position; }

////////////////////////////////////////////////////////////////////////////////
// Implement the methods expected by the HBIL header
float	FetchDepth( float2 _pixelPosition, float _mipLevel ) {
//	return _tex_sourceRadiance.SampleLevel( LinearClamp, _pixelPosition / _resolution, _mipLevel ).w;
	return Z_FAR * _tex_depth.SampleLevel( LinearClamp, _pixelPosition / _resolution, _mipLevel );
}

float3	FetchRadiance( float2 _pixelPosition, float _mipLevel ) {
	return _tex_sourceRadiance.SampleLevel( LinearClamp, _pixelPosition / _resolution, _mipLevel ).xyz;
}

float2	ComputeMipLevel( float2 _radius, float2 _radialStepSizes ) {
	float	radiusPixel = _radius.x;
	float	deltaRadius = _radialStepSizes.x;
	float	pixelArea = PI / (2.0 * MAX_ANGLES) * 2.0 * radiusPixel * deltaRadius;
//	return 0.5 * log2( pixelArea ) * _bilateralValues;
	return 0.5 * log2( pixelArea ) * float2( 0, 2 );	// Unfortunately, sampling lower mips for depth gives very nasty halos! Maybe use max depth? Meh. Not conclusive either...
	return 1.5 * 0.5 * log2( pixelArea );
	return 0.5 * log2( pixelArea );
}

float	BilateralFilterDepth( float _centralZ, float _previousDeltaZ, float _newDeltaZ, float _horizonCosTheta, float _newCosTheta, float _radius_m ) {
//Il fout grave la merde!

//return 1.0 - pow( saturate( _bilateralValues.x * _radius_m / _gatherSphereMaxRadius_m ), 2.0 * _bilateralValues.y );	// As per http://developer.download.nvidia.com/presentations/2008/SIGGRAPH/HBAO_SIG08b.pdf pp. 23
return 1;

	// Compute an horizon penalty when the horizon rises too quickly
	float	deltaTheta = saturate( (acos(_horizonCosTheta) - acos(_newCosTheta)) / PI );
//	float	penaltyCos = saturate( (deltaTheta - _bilateralValues.x) / _bilateralValues.y );
float	penaltyCos = saturate( (deltaTheta - 0.0) / 1.0 );

//return 1.0 - penaltyCos;

	// Compute a delta Z penalty when the depth rises too quickly
	float	relativeZ0 = max( 0.0, _previousDeltaZ ) / _centralZ;
	float	relativeZ1 = max( 0.0, _newDeltaZ ) / _centralZ;
//	float	penaltyZ = 1.0 - saturate( (relativeZ0 - relativeZ1 - _bilateralValues.z) / _bilateralValues.w );
float	penaltyZ = 1.0 - saturate( (relativeZ0 - relativeZ1 - 0.5) / 1.0 );

//return 1.0 - penaltyZ;

	// If the penalty flag is raised, we accept rising the horizon only if the difference in relative depth is not too high
//	return 1.0 - penaltyCos * penaltyZ / (40.0*_radius_m);
	return 1.0 - penaltyCos * penaltyZ / (100.0*_bilateralValues.x*_radius_m);
}


float3	SampleIrradiance_TEMP( float2 _csPosition, float4x3 _localCamera2World, float _centralZ, float2 _mipLevel, float2 _integralFactors, float _planeCosTheta, inout float _previousDeltaZ, inout float3 _previousRadiance, inout float _maxCosTheta ) {

//////////////////
// #TODO: Optimize!

// Transform camera-space position into screen space
float3	wsNeighborPosition = _localCamera2World[3] + _csPosition.x * _localCamera2World[0] + _csPosition.y * _localCamera2World[1];

float4	projPosition = mul( float4( wsNeighborPosition, 1.0 ), _World2Proj );
		projPosition.xyz /= projPosition.w;
float2	ssPosition = float2( 0.5 * (1.0 + projPosition.x) * _resolution.x, 0.5 * (1.0 - projPosition.y) * _resolution.y );


// Sample new depth and rebuild final world-space position
float	Z = FetchDepth( ssPosition, _mipLevel.x );
	
float3	wsView = wsNeighborPosition - _Camera2World[3].xyz;		// Neighbor world-space position (not projected), relative to camera
		wsView /= dot( wsView, _Camera2World[2].xyz );			// Scaled so its length against the camera's Z axis is 1
		wsView *= Z;											// Scaled again so its length agains the camera's Z axis equals our sampled Z

wsNeighborPosition = _Camera2World[3].xyz + wsView;				// Final reprojected world-space position

// Update horizon angle following eq. (3) from the paper
wsNeighborPosition -= _localCamera2World[3];					// Neighbor position, relative to central position
float3	csNeighborPosition = float3( dot( wsNeighborPosition, _localCamera2World[0] ), dot( wsNeighborPosition, _localCamera2World[1] ), dot( wsNeighborPosition, _localCamera2World[2] ) );
float	radius = length( csNeighborPosition.xy );
float	d = csNeighborPosition.z;
float	cosTheta = d / sqrt( radius*radius + d*d );				// Cosine to candidate horizon angle
//////////////////


	// Filter outlier horizon values
	float	bilateralWeight = BilateralFilterDepth( _centralZ, _previousDeltaZ, d, _maxCosTheta, cosTheta, radius );
	cosTheta = lerp( _planeCosTheta, cosTheta, bilateralWeight );	// Flatten to plane if rejected

	// Update any rising horizon
	if ( cosTheta <= _maxCosTheta )
		return 0.0;	// Below the horizon... No visible contribution.

	#if SAMPLE_NEIGHBOR_RADIANCE
		_previousRadiance = FetchRadiance( ssPosition, _mipLevel.y );
	#endif

	// Integrate over horizon difference (always from smallest to largest angle otherwise we get negative results!)
	float3	incomingRadiance = _previousRadiance * IntegrateSolidAngle( _integralFactors, cosTheta, _maxCosTheta );

// #TODO: Integrate with linear interpolation of irradiance as well??
// #TODO: Integrate with Fresnel F0!

	_maxCosTheta = cosTheta;	// Register a new positive horizon
	_previousDeltaZ = d;		// Accept new depth difference

	return incomingRadiance;
}

float3	GatherIrradiance_TEMP( float2 _csDirection, float4x3 _localCamera2World, float3 _csNormal, float _stepSize_meters, uint _stepsCount, float _centralZ, float3 _centralRadiance, out float3 _csBentNormal, out float _AO, inout float4 _DEBUG ) {

	// Pre-compute factors for the integrals
	float2	integralFactors_Front = ComputeIntegralFactors( _csDirection, _csNormal );
	float2	integralFactors_Back = ComputeIntegralFactors( -_csDirection, _csNormal );

	// Compute initial cos(angle) for front & back horizons
	// We do that by projecting the camera-space direction csDirection onto the tangent plane given by the normal
	//	then the cosine of the angle from the Z axis is simply given by the Pythagorean theorem:
	//                             P
	//			   N\  |Z		  -*-
	//				 \ |	  ---  ^
	//				  \|  ---      |
	//             --- *..........>+ csDirection
	//        --- 
	//
	float	hitDistance_Front = -dot( _csDirection, _csNormal.xy ) / _csNormal.z;
	float	planeCosTheta_Front = hitDistance_Front / sqrt( hitDistance_Front*hitDistance_Front + 1.0 );	// Assuming length(_csDirection) == 1
	float	planeCosTheta_Back = -planeCosTheta_Front;	// Back cosine is simply the mirror value

// Show horizon effect ON/OFF
//planeCosTheta_Front = -1.0;
//planeCosTheta_Back = -1.0;

	// Gather irradiance from front & back directions while updating the horizon angles at the same time
	float3	sumRadiance = 0.0;
	float3	previousRadiance_Front = _centralRadiance;
	float3	previousRadianceBack = _centralRadiance;
//*
	float2	csStep = _stepSize_meters * _csDirection;
	float2	csPosition_Front = 0.0;
	float2	csPosition_Back = 0.0;
	float	Z_Front = _centralZ;
	float	Z_Back = _centralZ;
	float	maxCosTheta_Front = planeCosTheta_Front;
	float	maxCosTheta_Back = planeCosTheta_Back;
	[loop]
	for ( uint stepIndex=0; stepIndex < _stepsCount; stepIndex++ ) {
		csPosition_Front += csStep;
		csPosition_Back -= csStep;

//		float2	mipLevel = ComputeMipLevel( radius, _radialStepSizes );
float2	mipLevel = 0.0;

		sumRadiance += SampleIrradiance_TEMP( csPosition_Front, _localCamera2World, _centralZ, mipLevel, integralFactors_Front, planeCosTheta_Front, Z_Front, previousRadiance_Front, maxCosTheta_Front );
		sumRadiance += SampleIrradiance_TEMP( csPosition_Back, _localCamera2World, _centralZ, mipLevel, integralFactors_Back, planeCosTheta_Back, Z_Back, previousRadianceBack, maxCosTheta_Back );
	}
//*/

	// Accumulate bent normal direction by rebuilding and averaging the front & back horizon vectors
	float2	ssNormal = float2( dot( _csNormal.xy, _csDirection ), _csNormal.z );	// Project normal onto the slice plane

	#if USE_NUMERICAL_INTEGRATION
		// Half brute force where we perform the integration numerically as a sum...
		//
		float	thetaFront = acos( maxCosTheta_Front );
		float	thetaBack = -acos( maxCosTheta_Back );

		float2	ssBentNormal = 0.0;
		for ( uint i=0; i < USE_NUMERICAL_INTEGRATION; i++ ) {
			float	theta = lerp( thetaBack, thetaFront, (i+0.5) / USE_NUMERICAL_INTEGRATION );
			float	sinTheta, cosTheta;
			sincos( theta, sinTheta, cosTheta );
			float2	ssOmega = float2( sinTheta, cosTheta );

			float	cosAlpha = saturate( dot( ssOmega, ssNormal ) );

cosAlpha = 1.0;	// No influence after all!!

			float	weight = cosAlpha * abs(sinTheta);		// cos(alpha) * sin(theta).dTheta  (be very careful to take abs(sin(theta)) because our theta crosses the pole and becomes negative here!)

			ssBentNormal += weight * ssOmega;
		}

		float	dTheta = (thetaFront - thetaBack) / USE_NUMERICAL_INTEGRATION;
		ssBentNormal *= dTheta;

		_csBentNormal = float3( ssBentNormal.x * _csDirection, ssBentNormal.y );
	#elif 1
		// Analytical solution for equations (5) and (6) from the paper
		// ==== WITHOUT NORMAL INFLUENCE ==== 
		// 
		#if USE_FAST_ACOS
			float	theta0 = -FastAcos( maxCosTheta_Back );
			float	theta1 = FastAcos( maxCosTheta_Front );
		#else
			float	theta0 = -acos( maxCosTheta_Back );
			float	theta1 = acos( maxCosTheta_Front );
		#endif
		float	cosTheta0 = maxCosTheta_Back;
		float	cosTheta1 = maxCosTheta_Front;
		float	sinTheta0 = -sqrt( 1.0 - cosTheta0*cosTheta0 );
		float	sinTheta1 = sqrt( 1.0 - cosTheta1*cosTheta1 );

		float	averageX = theta1 + theta0 - sinTheta0*cosTheta0 - sinTheta1*cosTheta1;
		float	averageY = 2.0 - cosTheta0*cosTheta0 - cosTheta1*cosTheta1;

		_csBentNormal = float3( averageX * _csDirection, averageY );	// Rebuild normal in camera space
	#else
		// Analytical solution for equations (5) and (6) from the paper
		// ==== WITH NORMAL INFLUENCE ==== 
		// These integrals are more complicated and we used to account for the dot product with the normal but that's not the way to compute the bent normal after all!!
		float	cosTheta0 = maxCosTheta_Front;
		float	cosTheta1 = maxCosTheta_Back;	// This should be in [-PI,0] but instead I take the absolute value so [0,PI] instead
		float	sinTheta0 = sqrt( 1.0 - cosTheta0*cosTheta0 );
		float	sinTheta1 = sqrt( 1.0 - cosTheta1*cosTheta1 );
		float	cosTheta0_3 = cosTheta0*cosTheta0*cosTheta0;
		float	cosTheta1_3 = cosTheta1*cosTheta1*cosTheta1;
		float	sinTheta0_3 = sinTheta0*sinTheta0*sinTheta0;
		float	sinTheta1_3 = sinTheta1*sinTheta1*sinTheta1;

		float	averageX = ssNormal.x * (cosTheta0_3 + cosTheta1_3 - 3.0 * (cosTheta0 + cosTheta1) + 4.0)
						 + ssNormal.y * (sinTheta0_3 - sinTheta1_3);

		float	averageY = ssNormal.x * (sinTheta0_3 - sinTheta1_3)
						 + ssNormal.y * (2.0 - cosTheta0_3 - cosTheta1_3);

		_csBentNormal = float3( averageX * _csDirection, averageY );	// Rebuild normal in camera space
	#endif

	// DON'T NORMALIZE THE RESULT NOW OR WE GET BIAS!
//	_csBentNormal = normalize( _csBentNormal );

	// Compute AO for this slice (in [0,2]!!)
	_AO = 2.0 - maxCosTheta_Back - maxCosTheta_Front;



_DEBUG = float4( _csBentNormal, 0 );


	return sumRadiance;
}


////////////////////////////////////////////////////////////////////////////////
// Computes bent cone & irradiance gathering from pixel's surroundings
struct PS_OUT {
	float4	irradiance : SV_TARGET0;
	float4	bentCone : SV_TARGET1;
};

PS_OUT	PS( float4 __Position : SV_POSITION ) {
	float2	UV = __Position.xy / _resolution;
	uint2	pixelPosition = uint2( floor( __Position.xy ) );
	float	noise = frac( _time + _tex_blueNoise[pixelPosition & 0x3F] );
//	float	noise = 0.0;
//	float	noise2 = frac( sin( 14357.91 * noise ) );

	// Setup camera ray
	float3	csView = BuildCameraRay( UV );
	float	Z2Distance = length( csView );
			csView /= Z2Distance;
	float3	wsView = mul( float4( csView, 0.0 ), _Camera2World ).xyz;

	// Read back depth, normal & central radiance value from last frame
	float	Z = FetchDepth( pixelPosition, 0.0 );

			Z -= 1e-2;	// !IMPORTANT! Prevent acnea by offseting the central depth a tiny bit closer

	float3	wsNormal = normalize( _tex_normal[pixelPosition].xyz );

	float3	centralRadiance = _tex_sourceRadiance[pixelPosition].xyz;	// Read back last frame's radiance value that we can use as a fallback for neighbor areas



//centralRadiance = _tex_emissive[pixelPosition];	// [18/02/12]



	// Compute local camera-space
	float3	wsPos = _Camera2World[3].xyz + Z * Z2Distance * wsView;
	float3	wsRight = normalize( cross( wsView, _Camera2World[1].xyz ) );
	float3	wsUp = cross( wsRight, wsView );
	float3	wsAt = -wsView;

	float4x3	localCamera2World = float4x3( wsRight, wsUp, wsAt, wsPos );

	// Compute local camera-space normal
	float3	N = float3( dot( wsNormal, wsRight ), dot( wsNormal, wsUp ), dot( wsNormal, wsAt ) );
			N.z = max( 1e-3, N.z );	// Make sure it's never 0!
//	float3	T, B;
//	BuildOrthonormalBasis( N, T, B );

	// Compute screen radius of gather sphere
	float	screenSize_m = 2.0 * Z * TAN_HALF_FOV;	// Vertical size of the screen in meters when extended to distance Z
	float	sphereRadius_pixels = _resolution.y * _gatherSphereMaxRadius_m / screenSize_m;
			sphereRadius_pixels = min( GATHER_SPHERE_MAX_RADIUS_P, sphereRadius_pixels );							// Prevent it to grow larger than our fixed limit
	float	radiusStepSize_pixels = max( 1.0, sphereRadius_pixels / MAX_SAMPLES );									// This gives us our radial step size in pixels
	uint	samplesCount = clamp( uint( ceil( sphereRadius_pixels / radiusStepSize_pixels ) ), 1, MAX_SAMPLES );	// Reduce samples count if possible
	float	radiusStepSize_meters = sphereRadius_pixels * screenSize_m / (samplesCount * _resolution.y);			// This gives us our radial step size in meters

	// Start gathering radiance and bent normal by subdividing the screen-space disk around our pixel into N slices
	float4	GATHER_DEBUG = 0.0;
	float3	sumIrradiance = 0.0;
	float	sumAO = 0.0;
	float3	csAverageBentNormal = 0.0;
	float	averageAO = 0.0;
	float	varianceAO = 0.0;
#if MAX_ANGLES > 1
	[loop]
	for ( uint angleIndex=0; angleIndex < MAX_ANGLES; angleIndex++ )
#else
	uint	angleIndex = 0;
#endif
	{
		float	phi = (angleIndex + noise) * PI / MAX_ANGLES;

//phi = 0.0;

		// Build camera-space and screen-space walk directions
		float2	csDirection;
		sincos( phi, csDirection.y, csDirection.x );

		// Gather irradiance and average cone direction for that slice
		float3	csBentNormal;
		float	AO;
		sumIrradiance += GatherIrradiance_TEMP( csDirection, localCamera2World, N, radiusStepSize_meters, samplesCount, Z, centralRadiance, csBentNormal, AO, GATHER_DEBUG );
		csAverageBentNormal += csBentNormal;
		sumAO += AO;

		// We're using running variance computation from https://www.johndcook.com/blog/standard_deviation/
		//	Avg(N) = Avg(N-1) + [V(N) - Avg(N-1)] / N
		//	S(N) = S(N-1) + [V(N) - Avg(N-1)] * [V(N) - Avg(N)]
		// And variance = S(finalN) / (finalN-1)
		//
		float	previousAverageAO = averageAO;
		averageAO += (AO - averageAO) / (1+angleIndex);
		varianceAO += (AO - previousAverageAO) * (AO - averageAO);
	}

	// Finalize bent cone
	csAverageBentNormal = normalize( csAverageBentNormal );

	// Use AO to compute cone angle
	sumAO /= 2.0 * MAX_ANGLES;	// Normalize
	float	cosAverageConeAngle = 1.0 - sumAO;

	#if MAX_ANGLES > 1
		varianceAO /= MAX_ANGLES;
	#endif
//	float	stdDeviation = PI * sqrt( varianceAO );		// Technically in [0,2PI]
	float	stdDeviation = 0.5 * sqrt( varianceAO );	// Now AO standard deviation in [0,1]

//stdDeviation = 0.0;

	// Finalize irradiance
	sumIrradiance *= PI / MAX_ANGLES;
	sumIrradiance = max( 0.0, sumIrradiance );

	// Write result
	PS_OUT	Out;
	Out.irradiance = float4( sumIrradiance, 0 );
	Out.bentCone = float4( max( 0.01, cosAverageConeAngle ) * csAverageBentNormal, stdDeviation );


//////////////////////////////////////////////
// WRITE DEBUG VALUE INTO BENT CONE BUFFER
float3	DEBUG_VALUE = float3( 1,0,1 );
DEBUG_VALUE = N;
DEBUG_VALUE = csAverageBentNormal;
DEBUG_VALUE = csAverageBentNormal.x * wsRight + csAverageBentNormal.y * wsUp + csAverageBentNormal.z * wsAt;	// World-space normal
//DEBUG_VALUE = cosAverageConeAngle;
//DEBUG_VALUE = dot( ssAverageBentNormal, N );
//DEBUG_VALUE = 0.01 * Z;
//DEBUG_VALUE = sphereRadius_pixels / GATHER_SPHERE_MAX_RADIUS_P;
//DEBUG_VALUE = 0.1 * (radiusStepSize_pixels-1);
//DEBUG_VALUE = 0.5 * float(samplesCount) / MAX_SAMPLES;
//DEBUG_VALUE = varianceConeAngle;
//DEBUG_VALUE = stdDeviation;
//DEBUG_VALUE = float3( GATHER_DEBUG.xy, 0 );
//DEBUG_VALUE = float3( GATHER_DEBUG.zw, 0 );
//DEBUG_VALUE = 0.4 * localCamera2World[3];
DEBUG_VALUE = GATHER_DEBUG.xyz;
//Out.bentCone = float4( DEBUG_VALUE, 1 );
//
//////////////////////////////////////////////

	return Out;
}