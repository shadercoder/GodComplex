﻿using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Data;
using System.Drawing;
using System.Linq;
using System.Text;
using System.Windows.Forms;

using RendererManaged;
using Nuaj.Cirrus.Utility;

namespace VoronoiVisualizer
{
	public partial class Form1 : Form
	{
		Device				m_Device = null;

		[System.Runtime.InteropServices.StructLayout( System.Runtime.InteropServices.LayoutKind.Sequential )]
		struct CB_Camera {
//			public float4x4		m_World2Camera;
			public float4x4		m_World2Proj;
		};

		[System.Runtime.InteropServices.StructLayout( System.Runtime.InteropServices.LayoutKind.Sequential )]
		struct CB_Mesh {
			public float4		m_Color;
		};

		[System.Runtime.InteropServices.StructLayout( System.Runtime.InteropServices.LayoutKind.Sequential )]
		struct SB_Neighbor {
			public float3		m_Position;
			public float3		m_Color;
		}

		ConstantBuffer< CB_Camera >		m_CB_Camera;
		ConstantBuffer< CB_Mesh >		m_CB_Mesh;
		StructuredBuffer< SB_Neighbor >	m_SB_Neighbors;
		Shader							m_Shader_RenderCellPlanes;
		Shader							m_Shader_RenderCellMesh;
		Primitive						m_Prim_Quad;

		WMath.Hammersley	m_Hammersley = new WMath.Hammersley();
		float3[]			m_NeighborPositions = null;
		float3[]			m_NeighborColors = null;

		Camera				m_Camera = new Camera();
		CameraManipulator	m_CameraManipulator = new CameraManipulator();

		public Form1()
		{
			InitializeComponent();

			m_Device = new Device();
			m_Device.Init( panel1.Handle, false, false );

			m_Shader_RenderCellPlanes = new Shader( m_Device, new ShaderFile( new System.IO.FileInfo( "RenderCellPlanes.hlsl" ) ), VERTEX_FORMAT.T2, "VS", null, "PS", null );
			m_Shader_RenderCellMesh = new Shader( m_Device, new ShaderFile( new System.IO.FileInfo( "RenderCellMesh.hlsl" ) ), VERTEX_FORMAT.P3, "VS", null, "PS", null );

			VertexT2[]	Vertices = new VertexT2[4] {
				new VertexT2() { UV = new float2( 0, 0 ) },
				new VertexT2() { UV = new float2( 0, 1 ) },
				new VertexT2() { UV = new float2( 1, 0 ) },
				new VertexT2() { UV = new float2( 1, 1 ) },
			};
			m_Prim_Quad = new Primitive( m_Device, 4, VertexT2.FromArray( Vertices ), null, Primitive.TOPOLOGY.TRIANGLE_STRIP, VERTEX_FORMAT.T2 );

			// Setup camera
			m_CB_Camera = new ConstantBuffer< CB_Camera >( m_Device, 0 );
			m_CB_Mesh = new ConstantBuffer< CB_Mesh >( m_Device, 1 );

			m_Camera.CreatePerspectiveCamera( 120.0f * (float) Math.PI / 180.0f, (float) panel1.Width / panel1.Height, 0.01f, 100.0f );
			m_Camera.CameraTransformChanged += new EventHandler( Camera_CameraTransformChanged );

			m_CameraManipulator.Attach( panel1, m_Camera );
			m_CameraManipulator.InitializeCamera( -0.1f * float3.UnitZ, float3.Zero, float3.UnitY );

			// Initalize random neighbors
			integerTrackbarControlNeighborsCount_ValueChanged( integerTrackbarControlNeighborsCount, 0 );

			Application.Idle += new EventHandler( Application_Idle );
		}

		void Camera_CameraTransformChanged( object sender, EventArgs e )
		{
			m_CB_Camera.m.m_World2Proj = m_Camera.World2Camera * m_Camera.Camera2Proj;
		}

		protected override void OnFormClosing( FormClosingEventArgs e )
		{
			if ( m_Prim_CellFaces != null ) {
				m_Prim_CellFaces.Dispose();
				m_Prim_CellEdges.Dispose();
			}

			m_Shader_RenderCellMesh.Dispose();
			m_Shader_RenderCellPlanes.Dispose();
			m_Prim_Quad.Dispose();
			m_SB_Neighbors.Dispose();
			m_CB_Mesh.Dispose();
			m_CB_Camera.Dispose();
			m_Device.Dispose();

			base.OnFormClosing( e );
		}

		void Application_Idle( object sender, EventArgs e )
		{
			if ( m_Device == null )
				return;

			// Update camera
			m_CB_Camera.UpdateData();

			// Clear
			m_Device.ClearDepthStencil( m_Device.DefaultDepthStencil, 1.0f, 0, true, false );
			m_Device.Clear( float4.Zero );

			// Render
			m_Device.SetRenderTarget( m_Device.DefaultTarget, m_Device.DefaultDepthStencil );
			if ( checkBoxRenderCell.Checked && m_Prim_CellFaces != null ) {
				// Render mesh
				if ( m_Shader_RenderCellMesh.Use() ) {
					m_Device.SetRenderStates( RASTERIZER_STATE.CULL_NONE, DEPTHSTENCIL_STATE.DISABLED, BLEND_STATE.ADDITIVE );

					// Render faces
					m_CB_Mesh.m.m_Color = new float4( 0.2f, 0.2f, 0, 1 );
					m_CB_Mesh.UpdateData();
					m_Prim_CellFaces.Render( m_Shader_RenderCellMesh );

					// Render faces
					m_Device.SetRenderStates( RASTERIZER_STATE.NOCHANGE, DEPTHSTENCIL_STATE.DISABLED, BLEND_STATE.DISABLED );
					m_CB_Mesh.m.m_Color = new float4( 1, 1, 0, 1 );
					m_CB_Mesh.UpdateData();
					m_Prim_CellEdges.Render( m_Shader_RenderCellMesh );
				}
			} else {
				// Render planes
				if ( m_Shader_RenderCellPlanes.Use() ) {
					m_Device.SetRenderStates( RASTERIZER_STATE.CULL_BACK, DEPTHSTENCIL_STATE.READ_WRITE_DEPTH_LESS, BLEND_STATE.DISABLED );

					m_SB_Neighbors.SetInput( 0 );

					m_Prim_Quad.RenderInstanced( m_Shader_RenderCellPlanes, m_SB_Neighbors.m.Length );
				}
			}

			m_Device.Present( false );
		}

		private void integerTrackbarControlNeighborsCount_ValueChanged( IntegerTrackbarControl _Sender, int _FormerValue )
		{
			int	NeighborsCount = integerTrackbarControlNeighborsCount.Value;
			if ( m_SB_Neighbors != null )
				m_SB_Neighbors.Dispose();
			m_SB_Neighbors = new StructuredBuffer< SB_Neighbor >( m_Device, NeighborsCount, true );

			WMath.Vector[]	Directions = null;
			if ( radioButtonHammersley.Checked ) {
				double[,]		Samples = m_Hammersley.BuildSequence( NeighborsCount, 2 );
				Directions = m_Hammersley.MapSequenceToSphere( Samples, false );
			} else {
				Random	TempRNG = new Random();
				Directions = new WMath.Vector[NeighborsCount];
				for ( int i=0; i < NeighborsCount; i++ ) {
					Directions[i] = new WMath.Vector( 2.0f * (float) TempRNG.NextDouble() - 1.0f, 2.0f * (float) TempRNG.NextDouble() - 1.0f, 2.0f * (float) TempRNG.NextDouble() - 1.0f );
					Directions[i].Normalize();
				}
			}

			Random	RNG = new Random( 1 );

			m_NeighborPositions = new float3[NeighborsCount];
			m_NeighborColors = new float3[NeighborsCount];
			for ( int NeighborIndex=0; NeighborIndex < NeighborsCount; NeighborIndex++ ) {
				float	Radius = 2.0f;	// Make that random!
				m_NeighborPositions[NeighborIndex] = Radius * new float3( Directions[NeighborIndex].x, Directions[NeighborIndex].y, Directions[NeighborIndex].z );

				float	R = (float) RNG.NextDouble();
				float	G = (float) RNG.NextDouble();
				float	B = (float) RNG.NextDouble();
				m_NeighborColors[NeighborIndex] = new float3( R, G, B );

				m_SB_Neighbors.m[NeighborIndex].m_Position = m_NeighborPositions[NeighborIndex];
				m_SB_Neighbors.m[NeighborIndex].m_Color = m_NeighborColors[NeighborIndex];
			}

			m_SB_Neighbors.Write();	// Upload
		}

		private void buttonReload_Click( object sender, EventArgs e )
		{
			if ( m_Device != null )
				m_Device.ReloadModifiedShaders();
		}

		private void radioButtonHammersley_CheckedChanged( object sender, EventArgs e )
		{
			integerTrackbarControlNeighborsCount_ValueChanged( integerTrackbarControlNeighborsCount, 0 );
		}

		private void radioButtonRandom_CheckedChanged( object sender, EventArgs e )
		{
			integerTrackbarControlNeighborsCount_ValueChanged( integerTrackbarControlNeighborsCount, 0 );
		}

		private void checkBoxSimulate_CheckedChanged( object sender, EventArgs e )
		{
			timer1.Enabled = checkBoxSimulate.Checked;
		}

		private void timer1_Tick( object sender, EventArgs e )
		{
			// Perform simulation
			int			NeighborsCount = m_NeighborPositions.Length;

			// Compute pressure forces
			float		F = 0.01f * floatTrackbarControlForce.Value;
			float3[]	Forces = new float3[NeighborsCount];
			for ( int i=0; i < NeighborsCount-1; i++ ) {
				float3	D0 = m_NeighborPositions[i].Normalized;
				for ( int j=i+1; j < NeighborsCount; j++ ) {
					float3	D1 = m_NeighborPositions[j].Normalized;

					float3	Dir = (D1 - D0).Normalized;

					float	Dot = D0.Dot( D1 ) - 1.0f;	// in [0,-2]
					float	Force = F * (float) Math.Exp( Dot );
					Forces[i] = Forces[i] - Force * Dir;	// Pushes 0 away from 1
					Forces[j] = Forces[j] + Force * Dir;	// Pushes 1 away from 0
				}
			}

			// Apply force
			for ( int i=0; i < NeighborsCount; i++ ) {
				float3	NewPosition = (m_NeighborPositions[i] + Forces[i]).Normalized;
				m_NeighborPositions[i] = NewPosition;
				m_SB_Neighbors.m[i].m_Position = NewPosition;
			}

			// Update
			m_SB_Neighbors.Write();
		}

		private void checkBoxRenderCell_CheckedChanged( object sender, EventArgs e )
		{
			if ( m_Prim_CellFaces == null )
				buttonBuildCell_Click( this, EventArgs.Empty );
		}

		#region Cell Building

		class	CellPolygon {

			float3		m_P;
			float3		m_T;
			float3		m_B;
			float3		m_N;
			public float3[]	m_Vertices = null;

			public CellPolygon( float3 _P, float3 _N ) {

				m_P = _P;
				m_N = _N;
				m_T = (float3.UnitY.Cross( m_N )).Normalized;
				m_B = m_N.Cross( m_T );

				// Start with 4 vertices
				const float	R = 10.0f;
				m_Vertices = new float3[] {
					m_P + R * (-m_T + m_B),
					m_P + R * (-m_T - m_B),
					m_P + R * ( m_T - m_B),
					m_P + R * ( m_T + m_B),
				};
			}

			// Cut polygon with a new plane, yielding a new polygon
			public void	Cut( float3 _P, float3 _N ) {
				List< float3 >	NewVertices = new List< float3 >();
				for ( int EdgeIndex=0; EdgeIndex < m_Vertices.Length; EdgeIndex++ ) {
					float3	P0 = m_Vertices[EdgeIndex+0];
					float3	P1 = m_Vertices[(EdgeIndex+1)%m_Vertices.Length];
					float	Dot0 = (P0 - _P).Dot( _N );
					float	Dot1 = (P1 - _P).Dot( _N );
					bool	InFront0 = Dot0 >= 0.0f;
					bool	InFront1 = Dot1 >= 0.0f;
					if ( !InFront0 && !InFront1 )
						continue;	// This edge is completely behind the cutting plane, skip it entirely

					if ( InFront0 && InFront1 ) {
						// This edge is completely in front of the cutting plane, add P1
						NewVertices.Add( P1 );
					} else {
						// The edge intersects the plane
						float3	D = P1 - P0;
						float	t = -Dot0 / D.Dot( _N );
						float3	I = P0 + t * D;
						NewVertices.Add( I );		// Add intersection no matter what
						if ( InFront1 )
							NewVertices.Add( P1 );	// Since the edge is entering the plane, also add end point
					}
				}

				m_Vertices = NewVertices.ToArray();
			}
		}

		Primitive	m_Prim_CellFaces = null;
		Primitive	m_Prim_CellEdges = null;
		private void buttonBuildCell_Click( object sender, EventArgs e )
		{
			if ( m_Prim_CellFaces != null ) {
				m_Prim_CellFaces.Dispose();
				m_Prim_CellEdges.Dispose();
				m_Prim_CellFaces = null;
				m_Prim_CellEdges = null;
			}

			List<VertexP3>	Vertices = new List<VertexP3>();
			List<uint>		Indices_Faces = new List<uint>();
			List<uint>		Indices_Edges = new List<uint>();

			for ( int FaceIndex=0; FaceIndex < m_NeighborPositions.Length; FaceIndex++ ) {
				float3	P = m_NeighborPositions[FaceIndex];
				float3	N = -P.Normalized;	// Pointing inward

				// Build the polygon by cutting it with all other neighbors
				CellPolygon	Polygon = new CellPolygon( P, N );
				for ( int NeighborIndex=0; NeighborIndex < m_NeighborPositions.Length; NeighborIndex++ )
					if ( NeighborIndex != FaceIndex ) {
						float3	Pn = m_NeighborPositions[NeighborIndex];
						float3	Nn = -Pn.Normalized;	// Pointing inward
						Polygon.Cut( Pn, Nn );
					}

				// Append vertices & indices for both faces & edges
				uint	VertexOffset = (uint) Vertices.Count;
				uint	VerticesCount = (uint) Polygon.m_Vertices.Length;
				foreach ( float3 Vertex in Polygon.m_Vertices ) {
					Vertices.Add( new VertexP3() { P = Vertex } );
				}
				for ( uint FaceTriangleIndex=0; FaceTriangleIndex < VerticesCount-2; FaceTriangleIndex++ ) {
					Indices_Faces.Add( VertexOffset + 0 );
					Indices_Faces.Add( VertexOffset + 1 + FaceTriangleIndex );
					Indices_Faces.Add( VertexOffset + 2 + FaceTriangleIndex );
				}
				for ( uint VertexIndex=0; VertexIndex < VerticesCount; VertexIndex++ ) {
					Indices_Edges.Add( VertexOffset + VertexIndex );
					Indices_Edges.Add( VertexOffset + (VertexIndex+1) % VerticesCount );
				}
			}

			m_Prim_CellFaces = new Primitive( m_Device, Vertices.Count, VertexP3.FromArray( Vertices.ToArray() ), Indices_Faces.ToArray(), Primitive.TOPOLOGY.TRIANGLE_LIST, VERTEX_FORMAT.P3 );
			m_Prim_CellEdges = new Primitive( m_Device, Vertices.Count, VertexP3.FromArray( Vertices.ToArray() ), Indices_Edges.ToArray(), Primitive.TOPOLOGY.LINE_LIST, VERTEX_FORMAT.P3 );
		}

		#endregion
	}
}