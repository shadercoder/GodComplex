#include "../API/Types.h"

const NjFloat2	NjFloat2::Zero( 0, 0 );
const NjFloat2	NjFloat2::One( 1, 1 );
const NjFloat2	NjFloat2::UnitX( 1, 0 );
const NjFloat2	NjFloat2::UnitY( 0, 1 );

const NjFloat3	NjFloat3::Zero( 0, 0, 0 );
const NjFloat3	NjFloat3::One( 1, 1, 1 );
const NjFloat3	NjFloat3::UnitX( 1, 0, 0 );
const NjFloat3	NjFloat3::UnitY( 0, 1, 0 );
const NjFloat3	NjFloat3::UnitZ( 0, 0, 1 );

const NjFloat4	NjFloat4::Zero( 0, 0, 0, 0 );
const NjFloat4	NjFloat4::One( 1, 1, 1, 1 );
const NjFloat4	NjFloat4::UnitX( 1, 0, 0, 0 );
const NjFloat4	NjFloat4::UnitY( 0, 1, 0, 0 );
const NjFloat4	NjFloat4::UnitZ( 0, 0, 1, 0 );
const NjFloat4	NjFloat4::UnitW( 0, 0, 0, 1 );

const NjFloat4x4	NjFloat4x4::Zero = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
const NjFloat4x4	NjFloat4x4::Identity = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 };

NjFloat4	NjFloat4::QuatFromAngleAxis( float _Angle, const NjFloat3& _Axis )
{
	_Angle *= 0.5f;

	float	c = cosf(_Angle);
	float	s = sinf(_Angle);

	return NjFloat4( s * _Axis, c );
}

NjFloat4x4  NjFloat4x4::Inverse() const
{
	float	Det = Determinant();
	ASSERT( abs(Det) > 1e-6f, "Matrix is not inversible !" );

	Det = 1.0f / Det;

	NjFloat4x4  Temp;
	Temp.m[4*0+0] = CoFactor( 0, 0 ) * Det;
	Temp.m[4*1+0] = CoFactor( 0, 1 ) * Det;
	Temp.m[4*2+0] = CoFactor( 0, 2 ) * Det;
	Temp.m[4*3+0] = CoFactor( 0, 3 ) * Det;
	Temp.m[4*0+1] = CoFactor( 1, 0 ) * Det;
	Temp.m[4*1+1] = CoFactor( 1, 1 ) * Det;
	Temp.m[4*2+1] = CoFactor( 1, 2 ) * Det;
	Temp.m[4*3+1] = CoFactor( 1, 3 ) * Det;
	Temp.m[4*0+2] = CoFactor( 2, 0 ) * Det;
	Temp.m[4*1+2] = CoFactor( 2, 1 ) * Det;
	Temp.m[4*2+2] = CoFactor( 2, 2 ) * Det;
	Temp.m[4*3+2] = CoFactor( 2, 3 ) * Det;
	Temp.m[4*0+3] = CoFactor( 3, 0 ) * Det;
	Temp.m[4*1+3] = CoFactor( 3, 1 ) * Det;
	Temp.m[4*2+3] = CoFactor( 3, 2 ) * Det;
	Temp.m[4*3+3] = CoFactor( 3, 3 ) * Det;

	return	Temp;
}

float	   NjFloat4x4::Determinant() const
{
	return m[0] * CoFactor( 0, 0 ) + m[1] * CoFactor( 0, 1 ) + m[2] * CoFactor( 0, 2 ) + m[3] * CoFactor( 0, 3 ); 
}

float	   NjFloat4x4::CoFactor( int x, int y ) const
{
	static int  IndexLoop[7] = { 0, 1, 2, 3, 0, 1, 2 };

	return	((	m[4*IndexLoop[x+1]+IndexLoop[y+1]]*m[4*IndexLoop[x+2]+IndexLoop[y+2]]*m[4*IndexLoop[x+3]+IndexLoop[y+3]] +
				m[4*IndexLoop[x+1]+IndexLoop[y+2]]*m[4*IndexLoop[x+2]+IndexLoop[y+3]]*m[4*IndexLoop[x+3]+IndexLoop[y+1]] +
				m[4*IndexLoop[x+1]+IndexLoop[y+3]]*m[4*IndexLoop[x+2]+IndexLoop[y+1]]*m[4*IndexLoop[x+3]+IndexLoop[y+2]] )

			-(	m[4*IndexLoop[x+3]+IndexLoop[y+1]]*m[4*IndexLoop[x+2]+IndexLoop[y+2]]*m[4*IndexLoop[x+1]+IndexLoop[y+3]] +
				m[4*IndexLoop[x+3]+IndexLoop[y+2]]*m[4*IndexLoop[x+2]+IndexLoop[y+3]]*m[4*IndexLoop[x+1]+IndexLoop[y+1]] +
				m[4*IndexLoop[x+3]+IndexLoop[y+3]]*m[4*IndexLoop[x+2]+IndexLoop[y+1]]*m[4*IndexLoop[x+1]+IndexLoop[y+2]] ))
			* (((x + y) & 1) == 1 ? -1.0f : +1.0f);
}

NjFloat4   operator*( const NjFloat4& a, const NjFloat4x4& b )
{
	NjFloat4	R;
	R.x = a.x * b.m[4*0+0] + a.y * b.m[4*1+0] + a.z * b.m[4*2+0] + a.w * b.m[4*3+0];
	R.y = a.x * b.m[4*0+1] + a.y * b.m[4*1+1] + a.z * b.m[4*2+1] + a.w * b.m[4*3+1];
	R.z = a.x * b.m[4*0+2] + a.y * b.m[4*1+2] + a.z * b.m[4*2+2] + a.w * b.m[4*3+2];
	R.w = a.x * b.m[4*0+3] + a.y * b.m[4*1+3] + a.z * b.m[4*2+3] + a.w * b.m[4*3+3];

	return R;
}


NjFloat4x4	NjFloat4x4::FromQuat( const NjFloat4& _Quat )
{
	NjFloat4	q = _Quat;
	q.Normalize();

	float	xs = 2.0f * q.x;
	float	ys = 2.0f * q.y;
	float	zs = 2.0f * q.z;

	float	wx, wy, wz, xx, xy, xz, yy, yz, zz;
	wx = q.w * xs;	wy = q.w * ys;	wz = q.w * zs;
	xx = q.x * xs;	xy = q.x * ys;	xz = q.x * zs;
	yy = q.y * ys;	yz = q.y * zs;	zz = q.z * zs;

	NjFloat4x4	Result;
	Result.m[4*0+0] = 1.0f - yy - zz;
	Result.m[4*0+1] =        xy + wz;
	Result.m[4*0+2] =        xz - wy;
	Result.m[4*0+3] = 0.0f;

	Result.m[4*1+0] =        xy - wz;
	Result.m[4*1+1] = 1.0f - xx - zz;
	Result.m[4*1+2] =        yz + wx;
	Result.m[4*1+3] = 0.0f;

	Result.m[4*2+0] =        xz + wy;
	Result.m[4*2+1] =        yz - wx;
	Result.m[4*2+2] = 1.0f - xx - yy;
	Result.m[4*2+3] = 0.0f;

	Result.m[4*3+0] = 0.0f;
	Result.m[4*3+1] = 0.0f;
	Result.m[4*3+2] = 0.0f;
	Result.m[4*3+3] = 1.0f;

	return	Result;
}

NjFloat4x4	NjFloat4x4::PRS( const NjFloat3& P, const NjFloat4& R, const NjFloat3& S )
{
	NjFloat4x4	Result = NjFloat4x4::FromQuat( R );

	Result.m[4*0+0] *= S.x;
	Result.m[4*0+1] *= S.x;
	Result.m[4*0+2] *= S.x;
	Result.m[4*0+3] *= S.x;
	Result.m[4*1+0] *= S.y;
	Result.m[4*1+1] *= S.y;
	Result.m[4*1+2] *= S.y;
	Result.m[4*1+3] *= S.y;
	Result.m[4*2+0] *= S.z;
	Result.m[4*2+1] *= S.z;
	Result.m[4*2+2] *= S.z;
	Result.m[4*2+3] *= S.z;

	Result.m[4*3+0] = P.x;
	Result.m[4*3+1] = P.y;
	Result.m[4*3+2] = P.z;

	return Result;
}

NjFloat4x4	NjFloat4x4::RotX( float _Angle )
{
	NjFloat4x4	R = NjFloat4x4::Identity;
	float C = cosf( _Angle );
	float S = sinf( _Angle );
	R.m[4*1+1] = C;		R.m[4*1+2] = S;
	R.m[4*2+1] = -S;	R.m[4*2+2] = C;
	return R;
}
NjFloat4x4	NjFloat4x4::RotY( float _Angle )
{
	NjFloat4x4	R = NjFloat4x4::Identity;
	float C = cosf( _Angle );
	float S = sinf( _Angle );
	R.m[4*0+0] = C;		R.m[4*0+2] = -S;
	R.m[4*2+0] = S;		R.m[4*2+2] = C;
	return R;
}
NjFloat4x4	NjFloat4x4::RotZ( float _Angle )
{
	NjFloat4x4	R = NjFloat4x4::Identity;
	float C = cosf( _Angle );
	float S = sinf( _Angle );
	R.m[4*0+0] = C;		R.m[4*0+1] = S;
	R.m[4*1+0] = -S;	R.m[4*1+1] = C;
	return R;
}
NjFloat4x4	NjFloat4x4::PYR( float _Pitch, float _Yaw, float _Roll )
{
	NjFloat4x4	Pitch = NjFloat4x4::RotX( _Pitch );
	NjFloat4x4	Yaw = NjFloat4x4::RotX( _Yaw );
	NjFloat4x4	Roll = NjFloat4x4::RotX( _Roll );

	NjFloat4x4	Result = Pitch * Yaw * Roll;
	return Result;
}


//////////////////////////////////////////////////////////////////////////
// Half floats encoding
#define F16_EXPONENT_BITS 0x1F
#define F16_EXPONENT_SHIFT 10
#define F16_EXPONENT_BIAS 15
#define F16_MANTISSA_BITS 0x3ff
#define F16_MANTISSA_SHIFT (23 - F16_EXPONENT_SHIFT)
#define F16_MAX_EXPONENT (F16_EXPONENT_BITS << F16_EXPONENT_SHIFT)

NjHalf::NjHalf( float value )
{
	U32 f32 = *((U32*) &value);
	raw = 0;

	// Decode IEEE 754 little-endian 32-bit floating-point value
	int sign = (f32 >> 16) & 0x8000;
	// Map exponent to the range [-127,128]
	int exponent = ((f32 >> 23) & 0xff) - 127;
	int mantissa = f32 & 0x007fffff;
	if ( exponent == 128 )
	{   // Infinity or NaN
		raw = U16( sign | F16_MAX_EXPONENT );
		if ( mantissa != 0 ) raw |= (mantissa & F16_MANTISSA_BITS);
	}
	else if ( exponent > 15 )
	{   // Overflow - flush to Infinity
		raw = U16( sign | F16_MAX_EXPONENT );
	}
	else if ( exponent > -15 )
	{   // Representable value
		exponent += F16_EXPONENT_BIAS;
		mantissa >>= F16_MANTISSA_SHIFT;
		raw = U16( sign | exponent << F16_EXPONENT_SHIFT | mantissa );
	}
	else
	{
		raw = U16(sign);
	}
}

NjHalf::operator float() const
{
	union 
	{
		float   f;
		U32	 ui;
	} f32;

	int sign = (raw & 0x8000) << 15;
	int exponent = (raw & 0x7c00) >> 10;
	int mantissa = (raw & 0x03ff);

	f32.f = 0.0f;
	if ( exponent == 0 )
	{
		if ( mantissa != 0 ) 
			f32.f = mantissa / float(1 << 24);
	}
	else if ( exponent == 31 )
	{
		f32.ui = sign | 0x7f800000 | mantissa;
	}
	else 
	{
		float scale, decimal;
		exponent -= 15;
		if ( exponent < 0 )
		{
			scale = float( 1.0 / (1 << -exponent) );
		}
		else 
		{
			scale = float( 1 << exponent );
		}
		decimal = 1.0f + (float) mantissa / (1 << 10);
		f32.f = scale * decimal;
	}
	
	if ( sign != 0 )
		f32.f = -f32.f;

	return f32.f;
}

NjFloat4x4  NjFloat4x4::operator*( const NjFloat4x4& b ) const
{
	NjFloat4x4  R;

	R.m[4*0+0] = m[4*0+0] * b.m[4*0+0] + m[4*0+1] * b.m[4*1+0] + m[4*0+2] * b.m[4*2+0] + m[4*0+3] * b.m[4*3+0];
	R.m[4*0+1] = m[4*0+0] * b.m[4*0+1] + m[4*0+1] * b.m[4*1+1] + m[4*0+2] * b.m[4*2+1] + m[4*0+3] * b.m[4*3+1];
	R.m[4*0+2] = m[4*0+0] * b.m[4*0+2] + m[4*0+1] * b.m[4*1+2] + m[4*0+2] * b.m[4*2+2] + m[4*0+3] * b.m[4*3+2];
	R.m[4*0+3] = m[4*0+0] * b.m[4*0+3] + m[4*0+1] * b.m[4*1+3] + m[4*0+2] * b.m[4*2+3] + m[4*0+3] * b.m[4*3+3];

	R.m[4*1+0] = m[4*1+0] * b.m[4*0+0] + m[4*1+1] * b.m[4*1+0] + m[4*1+2] * b.m[4*2+0] + m[4*1+3] * b.m[4*3+0];
	R.m[4*1+1] = m[4*1+0] * b.m[4*0+1] + m[4*1+1] * b.m[4*1+1] + m[4*1+2] * b.m[4*2+1] + m[4*1+3] * b.m[4*3+1];
	R.m[4*1+2] = m[4*1+0] * b.m[4*0+2] + m[4*1+1] * b.m[4*1+2] + m[4*1+2] * b.m[4*2+2] + m[4*1+3] * b.m[4*3+2];
	R.m[4*1+3] = m[4*1+0] * b.m[4*0+3] + m[4*1+1] * b.m[4*1+3] + m[4*1+2] * b.m[4*2+3] + m[4*1+3] * b.m[4*3+3];

	R.m[4*2+0] = m[4*2+0] * b.m[4*0+0] + m[4*2+1] * b.m[4*1+0] + m[4*2+2] * b.m[4*2+0] + m[4*2+3] * b.m[4*3+0];
	R.m[4*2+1] = m[4*2+0] * b.m[4*0+1] + m[4*2+1] * b.m[4*1+1] + m[4*2+2] * b.m[4*2+1] + m[4*2+3] * b.m[4*3+1];
	R.m[4*2+2] = m[4*2+0] * b.m[4*0+2] + m[4*2+1] * b.m[4*1+2] + m[4*2+2] * b.m[4*2+2] + m[4*2+3] * b.m[4*3+2];
	R.m[4*2+3] = m[4*2+0] * b.m[4*0+3] + m[4*2+1] * b.m[4*1+3] + m[4*2+2] * b.m[4*2+3] + m[4*2+3] * b.m[4*3+3];

	R.m[4*3+0] = m[4*3+0] * b.m[4*0+0] + m[4*3+1] * b.m[4*1+0] + m[4*3+2] * b.m[4*2+0] + m[4*3+3] * b.m[4*3+0];
	R.m[4*3+1] = m[4*3+0] * b.m[4*0+1] + m[4*3+1] * b.m[4*1+1] + m[4*3+2] * b.m[4*2+1] + m[4*3+3] * b.m[4*3+1];
	R.m[4*3+2] = m[4*3+0] * b.m[4*0+2] + m[4*3+1] * b.m[4*1+2] + m[4*3+2] * b.m[4*2+2] + m[4*3+3] * b.m[4*3+2];
	R.m[4*3+3] = m[4*3+0] * b.m[4*0+3] + m[4*3+1] * b.m[4*1+3] + m[4*3+2] * b.m[4*2+3] + m[4*3+3] * b.m[4*3+3];

	return R;
}

float&	NjFloat4x4::operator()( int _Row, int _Column )
{
	NjFloat4*	pRow = 0;
	switch ( _Row&3 )
	{
	case 0: pRow = (NjFloat4*) &m[4*0]; break;
	case 1: pRow = (NjFloat4*) &m[4*1]; break;
	case 2: pRow = (NjFloat4*) &m[4*2]; break;
	case 3: pRow = (NjFloat4*) &m[4*3]; break;
	}

	switch ( _Column&3 )
	{
	case 0: return pRow->x;
	case 1: return pRow->y;
	case 2: return pRow->z;
	case 3: return pRow->w;
	}
	return *((float*) 0);
}
